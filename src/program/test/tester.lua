module(..., package.seeall)

tester = {}

function tester:new ()
   local o = { packet_counter = 1 }


 function self:push()
   local i = assert(self.input.input, "input port not found")
   local o = assert(self.output.output, "output port not found")

   while not link.empty(i) and not link.full(o) do
      self:process_packet(i, o)
      self.packet_counter = self.packet_counter + 1
   end
 end

 function self:process_packet(i, o)
   local p = link.receive(i)

   -- drop every other packet
   if self.packet_counter % 2 == 0 then
      link.transmit(o, p)
   else
      packet.free(p)
   end
 end

   return setmetatable(o, {__index = tester})
   --return setmetatable(self, {__index = tester})
end

