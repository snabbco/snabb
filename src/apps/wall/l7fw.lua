module(..., package.seeall)

local link   = require("core.link")
local packet = require("core.packet")

L7Fw = {}
L7Fw.__index = L7Fw

-- create a new firewall app object given an instance of Scanner
-- and firewall rules
-- FIXME: for now, the rules are just a Lua table mapping a
--        protocol name to a policy "accept" or "drop"
--        we may want to have a real rule language, plus pflua
--        integration(?)
function L7Fw:new(config)
   local obj = { scanner = config.scanner, rules = config.rules }
   return setmetatable(obj, self)
end

function L7Fw:push()
   local i       = assert(self.input.input, "input port not found")
   local o       = assert(self.output.output, "output port not found")
   local rules   = self.rules
   local scanner = self.scanner

   while not link.empty(i) do
      local pkt  = link.receive(i)
      local flow = scanner:get_flow(pkt)

      if flow then
         local name   = scanner:protocol_name(flow.protocol)
         local policy = rules[name] or rules["default"]

         if policy == "accept" then
            link.transmit(o, pkt)
         elseif policy == "drop" then
            packet.free(pkt)
         -- TODO: what should the default policy be if there is none specified?
         else
            link.transmit(o, pkt)
         end
      else
         -- TODO: we may wish to have a default policy for packets
         --       without detected flows instead of just forwarding
         link.transmit(o, pkt)
      end
   end
end
