-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

-- http://tools.ietf.org/html/draft-mkonstan-keyed-ipv6-tunnel-01

-- TODO: generalize
local AF_INET6 = 10

local ffi = require("ffi")
local C = ffi.C
local bit = require("bit")

local app = require("core.app")
local link = require("core.link")
local lib = require("core.lib")
local packet = require("core.packet")
local config = require("core.config")
local counter = require("core.counter")

local macaddress = require("lib.macaddress")

local pcap = require("apps.pcap.pcap")
local basic_apps = require("apps.basic.basic_apps")

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
local function prepare_header_template ()
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

SimpleKeyedTunnel = {
   config = {
      -- string, ipv6 address
      local_address = {required=true},
      remote_address = {required=true},
      -- 8 bytes hex string
      local_cookie = {required=true},
      remote_cookie = {required=true},
      -- unsigned number, must fit to uint32_t
      local_session = {},
      -- string, MAC address (for testing)
      default_gateway_MAC = {},
      -- unsigned integer <= 255
      hop_limit = {}
   },
   shm = { rxerrors              = {counter},
           length_errors         = {counter},
           protocol_errors       = {counter},
           cookie_errors         = {counter},
           remote_address_errors = {counter},
           local_address_errors  = {counter} }
}

function SimpleKeyedTunnel:new (conf)
   assert(
         type(conf.local_cookie) == "string"
         and #conf.local_cookie <= 16,
         "local_cookie should be 8 bytes hex string"
      )
   assert(
         type(conf.remote_cookie) == "string"
         and #conf.remote_cookie <= 16,
         "remote_cookie should be 8 bytes hex string"
      )
   local header = header_array_ctype(HEADER_SIZE)
   ffi.copy(header, header_template, HEADER_SIZE)
   local local_cookie = lib.hexundump(conf.local_cookie, 8, false)
   ffi.copy(
         header + COOKIE_OFFSET,
         local_cookie,
         #local_cookie
      )

   -- convert dest, sorce ipv6 addressed to network order binary
   local result =
      C.inet_pton(AF_INET6, conf.local_address, header + SRC_IP_OFFSET)
   assert(result == 1,"malformed IPv6 address: " .. conf.local_address)

   result =
      C.inet_pton(AF_INET6, conf.remote_address, header + DST_IP_OFFSET)
   assert(result == 1,"malformed IPv6 address: " .. conf.remote_address)

   -- store casted pointers for fast matching
   local remote_address = ffi.cast(paddress_ctype, header + DST_IP_OFFSET)
   local local_address = ffi.cast(paddress_ctype, header + SRC_IP_OFFSET)

   local remote_cookie_s = lib.hexundump(conf.remote_cookie, 8, false)
   local remote_cookie = ffi.new(cookie_ctype)
   ffi.copy(remote_cookie, remote_cookie_s, #remote_cookie_s)

   if conf.local_session then
      local psession = ffi.cast(psession_id_ctype, header + SESSION_ID_OFFSET)
      psession[0] = lib.htonl(conf.local_session)
   end

   if conf.default_gateway_MAC then
      local mac = assert(macaddress:new(conf.default_gateway_MAC))
      ffi.copy(header + DST_MAC_OFFSET, mac.bytes, 6)
   end

   if conf.hop_limit then
      assert(type(conf.hop_limit) == 'number' and
          conf.hop_limit <= 255, "invalid hop limit")
      header[HOP_LIMIT_OFFSET] = conf.hop_limit
   end

   local o =
   {
      header = header,
      remote_address = remote_address,
      local_address = local_address,
      remote_cookie = remote_cookie[0]
   }

   return setmetatable(o, {__index = SimpleKeyedTunnel})
end

function SimpleKeyedTunnel:push()
   -- encapsulation path
   local l_in = self.input.decapsulated
   local l_out = self.output.encapsulated
   assert(l_in and l_out)

   while not link.empty(l_in) do
      local p = link.receive(l_in)
      p = packet.prepend(p, self.header, HEADER_SIZE)
      local plength = ffi.cast(plength_ctype, p.data + LENGTH_OFFSET)
      plength[0] = lib.htons(SESSION_COOKIE_SIZE + p.length - HEADER_SIZE)
      link.transmit(l_out, p)
   end

   -- decapsulation path
   l_in = self.input.encapsulated
   l_out = self.output.decapsulated
   assert(l_in and l_out)
   while not link.empty(l_in) do
      local p = link.receive(l_in)
      -- match next header, cookie, src/dst addresses
      local drop = true
      repeat
         if p.length < HEADER_SIZE then
            counter.add(self.shm.length_errors)
            break
         end
         local next_header = ffi.cast(next_header_ctype, p.data + NEXT_HEADER_OFFSET)
         if next_header[0] ~= L2TPV3_NEXT_HEADER then
            counter.add(self.shm.protocol_errors)
            break
         end

         local cookie = ffi.cast(pcookie_ctype, p.data + COOKIE_OFFSET)
         if cookie[0] ~= self.remote_cookie then
            counter.add(self.shm.cookie_errors)
            break
         end

         local remote_address = ffi.cast(paddress_ctype, p.data + SRC_IP_OFFSET)
         if remote_address[0] ~= self.remote_address[0] or
            remote_address[1] ~= self.remote_address[1]
         then
            counter.add(self.shm.remote_address_errors)
            break
         end

         local local_address = ffi.cast(paddress_ctype, p.data + DST_IP_OFFSET)
         if local_address[0] ~= self.local_address[0] or
            local_address[1] ~= self.local_address[1]
         then
            counter.add(self.shm.local_address_errors)
            break
         end

         drop = false
      until true

      if drop then
         counter.add(self.shm.rxerrors)
         -- discard packet
         packet.free(p)
      else
         p = packet.shiftleft(p, HEADER_SIZE)
         link.transmit(l_out, p)
      end
   end
end

-- prepare header template to be used by all apps
prepare_header_template()

function selftest ()
   print("Keyed IPv6 tunnel selftest")
   local ok = true
   local Synth = require("apps.test.synth").Synth
   local Match = require("apps.test.match").Match
   local tunnel_config = {
      local_address = "00::2:1",
      remote_address = "00::2:1",
      local_cookie = "12345678",
      remote_cookie = "12345678",
      default_gateway_MAC = "a1:b2:c3:d4:e5:f6"
   } -- should be symmetric for local "loop-back" test

   local c = config.new()
   config.app(c, "tunnel", SimpleKeyedTunnel, tunnel_config)
   config.app(c, "match", Match)
   config.app(c, "comparator", Synth)
   config.app(c, "source", Synth)
   config.link(c, "source.output -> tunnel.decapsulated")
   config.link(c, "comparator.output -> match.comparator")
   config.link(c, "tunnel.encapsulated -> tunnel.encapsulated")
   config.link(c, "tunnel.decapsulated -> match.rx")
   app.configure(c)

   app.main({duration = 0.0001, report = {showapps=true,showlinks=true}})
   -- Check results
   if #engine.app_table.match:errors() ~= 0 then
      ok = false
   end

   local c = config.new()
   config.app(c, "source", basic_apps.Source)
   config.app(c, "tunnel", SimpleKeyedTunnel, tunnel_config)
   config.app(c, "sink", basic_apps.Sink)
   config.link(c, "source.output -> tunnel.decapsulated")
   config.link(c, "tunnel.encapsulated -> tunnel.encapsulated")
   config.link(c, "tunnel.decapsulated -> sink.input")
   app.configure(c)

   print("run simple one second benchmark ...")
   app.main({duration = 1})

   if not ok then
      print("selftest failed")
      os.exit(1)
   end
   print("selftest passed")

end
