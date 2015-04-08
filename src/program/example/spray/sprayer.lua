module(..., package.seeall)

local pcap = require("apps.pcap.pcap")
local link = require("core.link")
local packet = require("core.packet")

Sprayer = {}

function Sprayer:new(arg)
   self.packet_counter = 1
   return setmetatable({}, {__index = Sprayer})
end

function Sprayer:push()
   local i = assert(self.input.input, "input port not found")
   local o = assert(self.output.output, "output port not found")

   while not link.empty(i) and not link.full(o) do
      self:process_packet(i, o)
      self.packet_counter = self.packet_counter + 1
   end
end

function Sprayer:process_packet(i, o)
   local p = link.receive(i)

   -- drop every other packet
   if self.packet_counter % 2 == 0 then
      link.transmit(o, p)
   else
      packet.free(p)
   end
end
