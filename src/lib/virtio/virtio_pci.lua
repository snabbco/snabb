-- Application to connect to a virtio-net driver implementation
--
-- Licensed under the Apache 2.0 license
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Copyright (c) 2015 Virtual Open Systems
--

module(..., package.seeall)

local debug = _G.developer_debug

local ffi       = require("ffi")
local C         = ffi.C
local S         = require('syscall')
local pci       = require("lib.hardware.pci")
local bit       = require('bit')

local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift

local RESET = 0
local ACKNOWLEDGE = 1
local DRIVER = 2
local DRIVER_OK = 4
local FEATURES_OK = 8
local FAILED = 128

local VIRTIO_PCI_QUEUE_ADDR_SHIFT = 12 -- the default page bit

VirtioPci = subClass(nil)
VirtioPci._name = "virtio pci"

-- Parses a C struct description
-- and creates a table which maps each field name
-- to size, offset and ctype. An example string argument:
-- [[
--    uint32_t a;
--    uint16_t b;
-- ]]
--
-- This will create a table with the following content:
-- { a = { fieldname = "a", ct = cdata<unsigned int>, size = 4, offset = 0},
--   b = { fieldname = "b", ct = cdata<unsigned short>, size = 2, offset = 4} }
local function fstruct(def)
   local struct = {}
   local offset = 0
   for ct, fld in def:gmatch('([%a_][%w_]*)%s+([%a_][%w_]*);') do
      ct = ffi.typeof(ct)
      struct[fld] = {
         fieldname = fld,
         ct = ct,
         size = ffi.sizeof(ct),
         offset = offset,
      }
      offset = offset + struct[fld].size
   end
   return struct, offset
end

-- Takes a field description as created by the fstruct function
-- and a file descriptor. A value of the field specified ctype,
-- size and offset is read from the file designated from the fd
local function fieldrd(field, fd)
   local buf = ffi.typeof('$ [1]', field.ct)()
   local r, err = fd:pread(buf, field.size, field.offset)
   if not r then error(err) end
   return buf[0]
end

-- Takes a field description as created by the fstruct function,
-- a file descriptor and a value. The value is written in the file,
-- specified by the fd, at the offset specified by the field
local function fieldwr(field, fd, val)
   local buf = ffi.typeof('$ [1]', field.ct)()
   buf[0] = val
   assert(fd:seek(field.offset))
   local r, err = fd:write(buf, field.size)
   if not r then error(err) end
   return buf[0]
end

local virtio_pci_bar0 = fstruct[[
   uint32_t host_features;
   uint32_t guest_features;
   uint32_t queue_pfn;
   uint16_t queue_num;
   uint16_t queue_sel;
   uint16_t queue_notify;
   uint8_t status;
   uint8_t isr;
   uint16_t config_vector;
   uint16_t queue_vector;
]]

local
function open_bar (fname, struct)
   local fd, err = S.open(fname, 'rdwr')
   if not fd then error(err) end
   return setmetatable ({
      fd = fd,
      struct = struct,
      close = function(self) return self.fd:close() end,
   }, {
      __index = function (self, key)
         return fieldrd(self.struct[key], self.fd)
      end,
      __newindex = function (self, key, value)
         return fieldwr(self.struct[key], self.fd, value)
      end,
   })
end

function VirtioPci:new(pciaddr)
   local o = VirtioPci:superClass().new(self)

   pci.unbind_device_from_linux (pciaddr)

   o._bar = open_bar(pci.path(pciaddr..'/resource0'), virtio_pci_bar0)

   return o
end

function VirtioPci:free()
   self._bar:close()
   VirtioPci:superClass().free(self)
end

function VirtioPci:set_status(status)
   local bar = self._bar
   bar.status = bor(bar.status, status)
end

function VirtioPci:reset()
   self._bar.status = 0
end

function VirtioPci:acknowledge()
   self:set_status(ACKNOWLEDGE)
end

function VirtioPci:driver()
   self:set_status(DRIVER)
end

function VirtioPci:features_ok()
   self:set_status(FEATURES_OK)
end

function VirtioPci:driver_ok()
   self:set_status(DRIVER_OK)
end

function VirtioPci:failed()
   self:set_status(FAILED)
end

function VirtioPci:set_guest_features(min_features, want_features)
   local bar = self._bar
   local features = bar.host_features
   if debug then print('host_features', features) end
   if band(features, min_features) ~= min_features then
      self:failed()
      return "doesn't provide minimum features"
   end
   if debug then print('set features to:', band(features, want_features)) end
   bar.guest_features = band(features, want_features)
   self:features_ok()
   if debug then print('got features: ', bar.host_features, bar.guest_features) end
   if band(bar.status, FEATURES_OK) ~= FEATURES_OK then
      self:failed()
      return "feature set wasn't accepted by device"
   end
end

function VirtioPci:get_queue_num(n)
   local bar = self._bar

   bar.queue_sel = n
   local queue_num = bar.queue_num

   if queue_num == 0 then return end

   if debug then print(('queue %d: size: %d'):format(n, queue_num)) end
   return queue_num
end

function VirtioPci:set_queue_vring(n, physaddr)
   local bar = self._bar
   bar.queue_sel = n

   bar.queue_pfn = rshift(physaddr, VIRTIO_PCI_QUEUE_ADDR_SHIFT)
end

function VirtioPci:disable_queue(n)
   local bar = self._bar
   bar.queue_sel = n
   bar.queue_pfn = 0
end

function VirtioPci:notify_queue(n)
   local bar = self._bar
   bar.queue_notify = n
end
