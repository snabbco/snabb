module(..., package.seeall)

local ffi      = require("ffi")
local lib      = require("core.lib")
local metadata = require("apps.rss.metadata")

local metadata_get = metadata.get
local ntohs = lib.ntohs

local types = {
   record_t = ffi.typeof([[
      struct {
         uint8_t type;
         uint16_t version;
         uint16_t length;
         uint8_t data[0];
      } __attribute__((packed))
   ]]),
   handshake_t = ffi.typeof([[
      struct {
         uint8_t msg_type;
         uint8_t length_msb;
         uint16_t length;
         uint8_t data[0];
      } __attribute__((packed))
   ]]),
   client_hello_t = ffi.typeof([[
      struct {
         uint16_t version;
         uint8_t random[32];
         uint8_t data[0];
      } __attribute__((packed))
   ]]),
   lv1_t = ffi.typeof([[
      struct {
        uint8_t length;
        uint8_t data[0];
      } __attribute__((packed))
   ]]),
   lv2_t = ffi.typeof([[
      struct {
        uint16_t length;
        uint8_t data[0];
      } __attribute__((packed))
   ]]),
   extensions_t = ffi.typeof([[
      struct {
        uint16_t length;
        uint8_t  data[0];
      } __attribute__((packed))
   ]]),
   tlv_t = ffi.typeof([[
      struct {
        uint16_t type;
        uint16_t length;
        uint8_t  value[0];
      } __attribute__((packed))
   ]]),
   sni_t = ffi.typeof([[
      struct {
        uint16_t list_length;
        uint8_t name_type;
        uint16_t name_length;
        uint8_t name[0];
      } __attribute__((packed))
   ]])
}
local ptrs = {}
for n, t in pairs(types) do
   ptrs[n] = ffi.typeof("$*", t)
end

local function skip_lv1(data)
   local tlv = ffi.cast(ptrs.lv1_t, data)
   return tlv.data + tlv.length
end

local function skip_lv2(data)
   local tlv = ffi.cast(ptrs.lv2_t, data)
   return tlv.data + ntohs(tlv.length)
end

local function tcp_header_size(l4)
   local offset = bit.rshift(ffi.cast("uint8_t*", l4)[12], 4)
   return offset * 4
end

function accumulate(self, entry, pkt)
   local md = metadata_get(pkt)
   -- The TLS handshake starts right after the TCP handshake,
   -- i.e. either in the second (piggy-backed on the handshake ACK) or
   -- third packet of the flow.
   local payload = md.l4 + tcp_header_size(md.l4)
   -- The effective payload size is the amount of the payload that is
   -- actually present. This can be smaller than the actual payload
   -- size if the packet has been truncated, e.g. by a port-mirror. It
   -- can also be larger if the packet has been padded to the minimum
   -- frame size (64 bytes). This can be safely ignored.
   local eff_payload_size = pkt.length - md.l3_offset - (payload - md.l3)
   if ((entry.packetDeltaCount == 1 or -- SYN
        (entry.packetDeltaCount == 2 and eff_payload_size == 0) or -- Empty ACK
        entry.packetDeltaCount > 3)) then
      return
   end
   local record = ffi.cast(ptrs.record_t, payload)
   -- Handshake record?
   if record.type ~= 22 then return end
   -- We assume that the record is completely contained in the first
   -- data segment.
   if ntohs(record.length) > eff_payload_size then return end
   local handshake = ffi.cast(ptrs.handshake_t, record.data)
   -- Client Hello?
   if handshake.msg_type ~= 1 then return end
   local client_hello = ffi.cast(ptrs.client_hello_t, handshake.data)
   -- Extensions are only supported since TLS 1.2
   if ntohs(client_hello.version) < 0x0303 then return end
   -- Skip session ID
   local tmp = skip_lv1(client_hello.data)
   -- Skip cipher suits
   tmp = skip_lv2(tmp)
   -- Skip compress methods
   tmp = skip_lv1(tmp)
   local extensions = ffi.cast(ptrs.extensions_t, tmp)
   -- Extensions present?
   if extensions == handshake.data + ntohs(handshake.length) then return end
   local extensions_length = ntohs(extensions.length)
   -- Find the SNI extension
   local extension = extensions.data
   while (extensions_length > 0) do
      local tlv = ffi.cast(ptrs.tlv_t, extension)
      if ntohs(tlv.type) == 0 then
         -- SNI, list of server names (RFC6066), extract the entry of
         -- type 0 (DNS hostname). This is the only type currently
         -- defined so must be the first and only entry in the
         -- list. To be future-proof, we should really skip names of
         -- different types.
         local sni = ffi.cast(ptrs.sni_t, tlv.value)
         if sni.name_type ~= 0 then return end
         local name_length = ntohs(sni.name_length)
         ffi.copy(entry.tlsSNI, sni.name, math.min(ffi.sizeof(entry.tlsSNI, name_length)))
         entry.tlsSNILength = name_length
         return
      end
      local length = ntohs(tlv.length)
      extensions_length = extensions_length - length - ffi.sizeof(types.tlv_t)
      extension = tlv.value + length
   end
end
