-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)
local ipv4 = require("lib.protocol.ipv4")
local ethernet = require("lib.protocol.ethernet")
local icmp = require("lib.protocol.icmp.header")
local dgram = require("lib.protocol.datagram")

PingEcho = {}

function PingEcho:new ()
   return setmetatable({}, {__index = PingEcho})
end

function PingEcho:pingecho (p, output)
    local d = dgram:new(p, ethernet)

    local eth = d:parse_match()
    local ip = d:parse_match()
    if ip == nil then 
        packet.free(p)
        return nil
    end
    
    local l4 = d:parse_match()
    if l4 == nil then
        packet.free(p)
        return nil
    end
   
    if l4:class() == icmp then 
        return p
    end

    packet.free(p)
end

function PingEcho:push ()
   local input  = assert(self.input.input, "input port not found")
   local output = assert(self.output.output, "output port not found")
   for i = 1, link.nreadable(input) do
      local p = link.receive(input)
      local outpkt = self:pingecho(p)
      if outpkt ~= nil then
         link.transmit(output, outpkt)
      end
   end
end

