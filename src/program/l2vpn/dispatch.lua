-- This app is a multiplexer/demultiplexer based on the IP source and
-- destination address of a packet.  It has a well-known port called
-- "south" that connects to the network and carries the multiplexed
-- traffic.
--
-- The app is created with a list of mappings of port names to IP
-- source and destination addresses for a particular address family
-- (ipv4 or ipv6).
--

module(..., package.seeall)
local ffi = require("ffi")
local lib = require("core.lib")
local ethernet = require("lib.protocol.ethernet")
local C = ffi.C

dispatch = {}

local dispatch_config_params = {
   afi = { required = true },
   links = { default = {} }
}
local link_config_params = {
   src = { required = true },
   dst = { required = true }
}

local afs = {
   ipv4 = {
      class = require("lib.protocol.ipv4"),
      offset = 12,
      size = 8,
      type = ffi.typeof[[
        union {
          struct {
            uint8_t src[4];
            uint8_t dst[4];
          } addrs;
          uint8_t bytes[8];
        }
      ]]
   },
   ipv6 = {
      class = require("lib.protocol.ipv6"),
      offset = 8,
      size = 32,
      type = ffi.typeof[[
        union {
          struct {
            uint8_t src[16];
            uint8_t dst[16];
          } addrs;
          uint8_t bytes[32];
        }
      ]]
  }
}
function dispatch:new (arg)
   local o = {}
   local conf = lib.parse(arg, dispatch_config_params)
   local af = afs[conf.afi]
   assert(af, "Invalid address family identifier "..conf.afi)
   o._offset = ethernet:sizeof() + af.offset
   o._size = af.size

   o._targets = {}
   for name, link in pairs(conf.links) do
      local conf = lib.parse(link, link_config_params)
      local template = af.type()
      C.memcpy(template.addrs.src, conf.src, ffi.sizeof(conf.src))
      C.memcpy(template.addrs.dst, conf.dst, ffi.sizeof(conf.dst))
      table.insert(o._targets, { template = template, link = name })
   end
   o._ntargets = #o._targets

   return setmetatable(o, { __index = dispatch })
end

function dispatch:push()
   local sin = self.input.south
   local sout = self.output.south

   for i = 1, self._ntargets do
      local t = self._targets[i]
      local tout = self.output[t.link]
      for _ = 1, link.nreadable(sin) do
         local p = link.receive(sin)
         if C.memcmp(t.template, p.data + self._offset, self._size) == 0 then
            link.transmit(tout, p)
         else
            link.transmit(sin, p)
         end
      end

      local tin = self.input[t.link]
      for _ = 1, link.nreadable(tin) do
         link.transmit(sout, link.receive(tin))
      end
   end

   for _ = 1, link.nreadable(sin) do
      packet.free(link.receive(sin))
   end
end
