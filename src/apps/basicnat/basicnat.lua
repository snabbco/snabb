module(..., package.seeall)

--- ### `basicnat` app: Implement http://www.ietf.org/rfc/rfc1631.txt Basic NAT

BasicNAT = {}

function BasicNAT:new ()
   return setmetatable({index = 1, packets = {}},
                       {__index=BasicNAT})
end

function BasicNAT:push ()
   local i, o = self.input.input, self.output.output
   local p = link.receive(i)
   link.transmit(o, p)
end
