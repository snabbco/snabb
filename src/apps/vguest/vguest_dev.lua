
module(..., package.seeall)

local ffi       = require("ffi")
local C         = ffi.C
local S         = require('syscall')
local pci       = require("lib.hardware.pci")
local bit       = require('bit')
local lib       = require("core.lib")
local link      = require("core.link")
local packet    = require("core.packet")
local checksum  = require("lib.checksum")
local gvring    = require('apps.vguest.guest_vring')
require('lib.virtio.virtio_h')


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

local function fieldrd(field, fd)
   local buf = ffi.typeof('$ [1]', field.ct)()
   local r, err = fd:pread(buf, field.size, field.offset)
   if not r then error(err) end
   return buf[0]
end

local function fieldwr(field, fd, val)
--    print ('fieldwr', field.ct, field.size, field.offset)
   local buf = ffi.typeof('$ [1]', field.ct)()
   buf[0] = val
--    print ('val:', val, buf, buf[0])
   assert(fd:seek(field.offset))
--    print ('tell:', fd:tell())
   local r, err = fd:write(buf, field.size)
   if not r then error(err) end
   return buf[0]
end

local function openBar(fname, struct)
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

virtio_pci_bar0 = fstruct[[
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


VGdev = {}
VGdev.__index = VGdev


function VGdev:new(args)
   local min_features = 0 -- C.VIRTIO_F_VERSION_1?
   local want_features = C.VIRTIO_NET_F_CSUM
                        + C.VIRTIO_NET_F_MAC
--                         + C.VIRTIO_F_VERSION_1
   pci.unbind_device_from_linux (args.pciaddr)

   local bar = openBar(pci.path(args.pciaddr..'/resource0'), virtio_pci_bar0)
--    for k,v in pairs(virtio_pci_bar0) do
--       print (string.format('%s: %X', v.fieldname, bar[v.fieldname]))
--    end

   bar.status = 0           -- reset device
   bar.status = bit.bor(bar.status, 1)           -- acknowledge
   -- check something
   bar.status = bit.bor(bar.status, 2)           -- driver
   local features = bar.host_features
   print ('host_features', features)
   if bit.band(features, min_features) ~= min_features then
      bar.status = bit.bor(bar.status, 128)      -- failure
      bar:close()
      return nil, "doesn't provide minimum features"
   end
   print ('set features to:', bit.band(features, want_features))
   bar.guest_features = bit.band(features, want_features)
   bar.status = bit.bor(bar.status, 8)           -- features_ok
   print ('got features: ', bar.host_features, bar.guest_features)
   if bit.band(bar.status, 8) ~= 8 then
      bar.status = bit.bor(bar.status, 128)      -- failure
      bar:close()
      return nil, "feature set wasn't accepted by device"
   end

   print ("enumerating queues...")
   local vqs = {}
   for qn = 0, 16 do
      bar.queue_sel = qn
      local queue_size = bar.queue_num
      if queue_size == 0 then break end

      print (string.format('queue %d: size: %d', qn, queue_size))
      local vring = gvring.allocate_vring(bar.queue_num)
      vqs[qn] = vring
      bar.queue_pfn = bit.rshift(vring.vring_physaddr, 12)      -- VIRTIO_PCI_QUEUE_ADDR_SHIFT
   end

   if not(vqs[0] and vqs[1]) then
      bar.status = bit.bor(bar.status, 128)      -- failure
      bar:close()
      return nil, "missing required virtqueues"
   end

   bar.status = bit.bor(bar.status, 4)           -- driver_ok

   return setmetatable({
      bar = bar,
      vqs = vqs,
   }, self)
end


function VGdev:close()
   for qn, vq in pairs(self.vqs) do
      self.bar.queue_sel = qn
      self.bar.queue_pfn = 0
   end
   self.bar:close()
end


function VGdev:can_transmit()
   return self.vqs[1]:can_add()
end

local pk_header = ffi.new([[
   struct {
      uint8_t flags;
      uint8_t gso_type;
      int16_t hdr_len;
      int16_t gso_size;
      int16_t csum_start;
      int16_t csum_offset;
//    int16_t num_buffers;    // only if MRG_RXBUF feature active
   }
]])
function VGdev:transmit(p)
   -- TODO: prepend header (5.1.6.2)
--    p:dump()
   ffi.fill(pk_header, ffi.sizeof(pk_header))
   local ethertype = ffi.cast('uint16_t*', p.data+12)[0]
   if ethertype == 0xDD86 or ethertype == 0x0080 then
      local startoffset = C.prepare_packet(p.data+14, p.length-14)
      if startoffset ~= nil then
--          print ('prepared', startoffset, startoffset[0], startoffset[1])
         pk_header.flags = 1      -- VIRTIO_NET_HDR_F_NEEDS_CSUM
         pk_header.csum_start = 14+startoffset[0]
         pk_header.csum_offset = startoffset[1]
      end
   end
   p:prepend(pk_header, ffi.sizeof(pk_header))
   self.vqs[1]:add(p)
end


function VGdev:sync_transmit()
   -- notify the device
   self.bar.queue_notify = 1

   -- free transmitted packets
   local txq = self.vqs[1]
   while txq:more_used() do
      local p = txq:get()
      if p ~= nil then p:free() end
   end
end


function VGdev:can_receive()
   return self.vqs[0]:more_used()
end


function VGdev:receive()
   local p = self.vqs[0]:get()
   p:shiftleft(ffi.sizeof(pk_header))
   return p
end


function VGdev:sync_receive()
end


function VGdev:can_add_receive_buffer()
   return self.vqs[0]:can_add()
end


function VGdev:add_receive_buffer(p)
   self.vqs[0]:add(p, ffi.sizeof(p.data))
end
