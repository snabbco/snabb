-- http://tools.ietf.org/html/draft-mkonstan-keyed-ipv6-tunnel-01

-- TODO: generalize
local AF_INET6 = 10

local ffi = require("ffi")
local C = ffi.C
local bit = require("bit")

local lib = require("core.lib")
local config = require("core.config")

local macaddress = require("lib.macaddress")


local header_struct_ctype = ffi.typeof[[
struct {
   // ethernet
   char dmac[6];
   char smac[6];
   uint16_t ethertype;
   // ipv6
   uint32_t flow_id; // version, tc, flow_id
   int16_t payload_length;
   int8_t  next_header;
   uint8_t hop_limit;
   char src_ip[16];
   char dst_ip[16];
   // tunnel
   uint32_t session_id;
   char cookie[8];
} __attribute__((packed))
]]

local HEADER_SIZE = ffi.sizeof(header_struct_ctype)

local header_array_ctype = ffi.typeof("uint8_t[?]")
local next_header_ctype = ffi.typeof("uint8_t*")
local cookie_ctype = ffi.typeof("uint64_t[1]")
local pcookie_ctype = ffi.typeof("uint64_t*")
local address_ctype = ffi.typeof("uint64_t[2]")
local paddress_ctype = ffi.typeof("uint64_t*")
local plength_ctype = ffi.typeof("int16_t*")
local psession_id_ctype = ffi.typeof("uint32_t*")

local DST_MAC_OFFSET = ffi.offsetof(header_struct_ctype, 'dmac')
local SRC_IP_OFFSET = ffi.offsetof(header_struct_ctype, 'src_ip')
local DST_IP_OFFSET = ffi.offsetof(header_struct_ctype, 'dst_ip')
local COOKIE_OFFSET = ffi.offsetof(header_struct_ctype, 'cookie')
local ETHERTYPE_OFFSET = ffi.offsetof(header_struct_ctype, 'ethertype')
local LENGTH_OFFSET =
   ffi.offsetof(header_struct_ctype, 'payload_length')
local NEXT_HEADER_OFFSET =
   ffi.offsetof(header_struct_ctype, 'next_header')
local SESSION_ID_OFFSET =
   ffi.offsetof(header_struct_ctype, 'session_id')
local FLOW_ID_OFFSET = ffi.offsetof(header_struct_ctype, 'flow_id')
local HOP_LIMIT_OFFSET = ffi.offsetof(header_struct_ctype, 'hop_limit')

local SESSION_COOKIE_SIZE = 12 -- 32 bit session and 64 bit cookie

-- Next Header.
-- Set to 0x73 to indicate that the next header is L2TPv3.
local L2TPV3_NEXT_HEADER = 0x73

local header_template = header_array_ctype(HEADER_SIZE)

-- fill header template with const values
do
   -- all bytes are zeroed after allocation

   -- IPv6
   header_template[ETHERTYPE_OFFSET] = 0x86
   header_template[ETHERTYPE_OFFSET + 1] = 0xDD

   -- Ver. Set to 0x6 to indicate IPv6.
   -- version is 4 first bits at this offset
   -- no problem to set others 4 bits to zeros - it is already zeros
   header_template[FLOW_ID_OFFSET] = 0x60

   header_template[HOP_LIMIT_OFFSET] = 64
   header_template[NEXT_HEADER_OFFSET] = L2TPV3_NEXT_HEADER

   -- For cases where both tunnel endpoints support one-stage resolution
   -- (IPv6 Address only), this specification recommends setting the
   -- Session ID to all ones for easy identification in case of troubleshooting.
   -- may be overridden by local_session options
   header_template[SESSION_ID_OFFSET] = 0xFF
   header_template[SESSION_ID_OFFSET + 1] = 0xFF
   header_template[SESSION_ID_OFFSET + 2] = 0xFF
   header_template[SESSION_ID_OFFSET + 3] = 0xFF
end

-- local variables that become the 'object'
local header
local remote_address = remote_address
local local_address = local_address
local remote_cookie = remote_cookie

do -- initialize things
   -- required fields:
   --   local_address, string, ipv6 address
   --   remote_address, string, ipv6 address
   --   local_cookie, 8 bytes hex string
   --   remote_cookie, 8 bytes hex string
   -- optional fields:
   --   local_session, unsigned number, must fit to uint32_t
   --   default_gateway_MAC, useful for testing
   --   hop_limit, override default hop limit 64
   assert(
         type(local_cookie) == "string"
         and #local_cookie <= 16,
         "local_cookie should be 8 bytes hex string"
      )
   assert(
         type(remote_cookie) == "string"
         and #remote_cookie <= 16,
         "remote_cookie should be 8 bytes hex string"
      )
   header = header_array_ctype(HEADER_SIZE)
   ffi.copy(header, header_template, HEADER_SIZE)
   local local_cookie = lib.hexundump(local_cookie, 8)
   ffi.copy(
         header + COOKIE_OFFSET,
         local_cookie,
         #local_cookie
      )

   -- convert dest, sorce ipv6 addressed to network order binary
   local result =
      C.inet_pton(AF_INET6, local_address, header + SRC_IP_OFFSET)
   assert(result == 1,"malformed IPv6 address: " .. local_address)

   result =
      C.inet_pton(AF_INET6, remote_address, header + DST_IP_OFFSET)
   assert(result == 1,"malformed IPv6 address: " .. remote_address)

   -- store casted pointers for fast matching
   remote_address = ffi.cast(paddress_ctype, header + DST_IP_OFFSET)
   local_address = ffi.cast(paddress_ctype, header + SRC_IP_OFFSET)

   remote_cookie = ffi.cast(pcookie_ctype, lib.hexundump(remote_cookie, 8))[0]

   if local_session then
      local psession = ffi.cast(psession_id_ctype, header + SESSION_ID_OFFSET)
      psession[0] = lib.htonl(local_session)
   end

   if default_gateway_MAC then
      local mac = assert(macaddress:new(default_gateway_MAC))
      ffi.copy(header + DST_MAC_OFFSET, mac.bytes, 6)
   end

   if hop_limit then
      assert(type(hop_limit) == 'number' and
         hop_limit <= 255, "invalid hop limit")
      header[HOP_LIMIT_OFFSET] = hop_limit
   end
end

function push()
   -- encapsulation path
   local l_in = input.decapsulated
   local l_out = output.encapsulated
   assert(l_in and l_out)

   while not link.empty(l_in) and not link.full(l_out) do
      local p = link.receive(l_in)
      packet.prepend(p, header, HEADER_SIZE)
      local plength = ffi.cast(plength_ctype, p.data + LENGTH_OFFSET)
      plength[0] = lib.htons(SESSION_COOKIE_SIZE + p.length - HEADER_SIZE)
      link.transmit(l_out, p)
   end

   -- decapsulation path
   l_in = input.encapsulated
   l_out = output.decapsulated
   assert(l_in and l_out)
   while not link.empty(l_in) and not link.full(l_out) do
      local p = link.receive(l_in)
      -- match next header, cookie, src/dst addresses
      local drop = true
      repeat
         if p.length < HEADER_SIZE then
            break
         end
         local next_header = ffi.cast(next_header_ctype, p.data + NEXT_HEADER_OFFSET)
         if next_header[0] ~= L2TPV3_NEXT_HEADER then
            break
         end

         local cookie = ffi.cast(pcookie_ctype, p.data + COOKIE_OFFSET)
         if cookie[0] ~= remote_cookie then
            break
         end

         local p_remote_address = ffi.cast(paddress_ctype, p.data + SRC_IP_OFFSET)
         if p_remote_address[0] ~= remote_address[0] or
            p_remote_address[1] ~= remote_address[1]
         then
            break
         end

         local p_local_address = ffi.cast(paddress_ctype, p.data + DST_IP_OFFSET)
         if p_local_address[0] ~= local_address[0] or
            p_local_address[1] ~= local_address[1]
         then
            break
         end

         drop = false
      until true

      if drop then
         -- discard packet
         packet.free(p)
      else
         packet.shiftleft(p, HEADER_SIZE)
         link.transmit(l_out, p)
      end
   end
end
