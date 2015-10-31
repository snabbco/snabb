module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local header = require("lib.protocol.header")
local lib = require("core.lib")
local bitfield = lib.bitfield
local ipsum = require("lib.checksum").ipsum
local ntohs, htons, ntohl, htonl =
   lib.ntohs, lib.htons, lib.ntohl, lib.htonl

-- GRE uses a variable-length header as specified by RFCs 2784 and
-- 2890.  The actual size is determined by flag bits in the base
-- header.  This implementation only supports the checksum and key
-- extensions.  Note that most of the flags specified in the original
-- specification of RFC1701 have been deprecated.

local gre = subClass(header)

ffi.cdef[[
      typedef struct {
         uint16_t bits; // Flags, version
         uint16_t protocol;
      } gre_h_t;
]]

-- Class variables
gre._name = "gre"
gre._ulp = {
   class_map = { [0x6558] = "lib.protocol.ethernet" },
   method    = 'protocol' }
gre:init(
   {
      [1] = ffi.typeof[[
            struct { gre_h_t h; }
      ]],
      [2] = ffi.typeof[[
            struct { gre_h_t h;
                     uint32_t key; }
      ]],
      [3] = ffi.typeof[[
            struct { gre_h_t h;
                     uint16_t csum;
                     uint16_t reserved1; }
      ]],
      [4] = ffi.typeof[[
            struct { gre_h_t h;
                     uint16_t csum;
                     uint16_t reserved1;
                     uint32_t key; }
      ]]
   })

local types = { base = 1, key = 2, csum = 3, csum_key = 4 }

-- Class methods

local default = { protocol = 0 }
function gre:new (config)
   local o = gre:superClass().new(self)
   local config = config or default
   local type = nil
   o._checksum, o._key = false, false
   if config then
      if config.checksum then
         type = 'csum'
         o._checksum = true
      end
      if config.key ~= nil then
         o._key = true
         if type then
            type = 'csum_key'
         else
            type = 'key'
         end
      end
   end
   if type then
      local header = o._headers[types[type]]
      o._header = header
      local data = header.data
      header.box[0] = ffi.cast(header.ptr_t, data)
      ffi.fill(data, ffi.sizeof(data))
      if o._key then
         lib.bitfield(16, data.h, 'bits', 2, 1, 1)
         o:key(config.key)
      end
      if o._checksum then
         lib.bitfield(16, data.h, 'bits', 0, 1, 1)
      end
   end
   o:protocol(config.protocol)
   return o
end

function gre:new_from_mem (mem, size)
   local o = gre:superClass().new_from_mem(self, mem, size)
   local header = o._header
   local data = header.box[0]
   -- Reserved bits and version MUST be zero.  We don't support
   -- the sequence number option, i.e. the 'S' flag (bit 3) must
   -- be cleared as well
   if bitfield(16, data.h, 'bits', 3, 13) ~= 0 then
      o:free()
      return nil
   end
   local type = nil
   if bitfield(16, data.h, 'bits', 0, 1) == 1 then
      type = 'csum'
      o._checksum = true
   else
      o._checksum = false
   end
   if bitfield(16, data.h, 'bits', 2, 1) == 1 then
      if type == 'csum' then
         type = 'csum_key'
      else
         type = 'key'
      end
      o._key = true
   else
      o._key = false
   end
   if type then
      local header = o._headers[types[type]]
      header.box[0] = ffi.cast(header.ptr_t, mem)
      o._header = header
   end
   return o
end

-- Instance methods

local function checksum(header, payload, length)
   local csum_in = header.csum;
   header.csum = 0;
   header.reserved1 = 0;
   local csum = ipsum(payload, length,
                      bit.bnot(ipsum(ffi.cast("uint8_t *", header),
                                     ffi.sizeof(header), 0)))
   header.csum = csum_in
   return csum
end

-- Returns nil if checksumming is disabled.  If payload and length is
-- supplied, the checksum is written to the header and returned to the
-- caller.  With nil arguments, the current checksum is returned.
function gre:checksum (payload, length)
   if not self._checksum then
      return nil
   end
   if payload ~= nil then
      -- Calculate and set the checksum
      self:header().csum = htons(checksum(self:header(), payload, length))
   end
   return ntohs(self:header().csum)
end

function gre:checksum_check (payload, length)
   if not self._checksum then
      return true
   end
   return checksum(self:header(), payload, length) == lib.ntohs(self:header().csum)
end

-- Returns nil if keying is disabled. Otherwise, the key is set to the
-- given value or the current key is returned if called with a nil
-- argument.
function gre:key (key)
   if not self._key then
      return nil
   end
   if key ~= nil then
      self:header().key = htonl(key)
   else
      return ntohl(self:header().key)
   end
end

function gre:protocol (protocol)
   if protocol ~= nil then
      self:header().h.protocol = htons(protocol)
   end
   return(ntohs(self:header().h.protocol))
end

return gre
