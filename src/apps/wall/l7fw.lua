module(..., package.seeall)

-- This module implements a level 7 firewall app that consumes the result
-- of DPI scanning done by l7spy.
--
-- The firewall rules are a table mapping protocol names to either
--   * a simple action ("drop", "reject", "accept")
--   * a pfmatch expression

local link   = require("core.link")
local packet = require("core.packet")
local match  = require("pf.match")

L7Fw = {}
L7Fw.__index = L7Fw

-- create a new firewall app object given an instance of Scanner
-- and firewall rules
function L7Fw:new(config)
   local obj = { scanner = config.scanner,
                 rules = config.rules,
                 -- this map tracks flows to compiled pfmatch functions
                 -- so that we only compile them once per flow
                 handler_map = {} }
   return setmetatable(obj, self)
end

-- called by pfmatch handlers, just drop the packet on the floor
function L7Fw:drop(pkt, len)
   packet.free(self.current_packet)
   return
end

-- called by pfmatch handler, handle rejection response
function L7Fw:reject(pkt, len)
   -- TODO: implement ICMP/TCP RST response
   packet.free(self.current_packet)
   return
end

-- called by pfmatch handler, forward packet
function L7Fw:accept(pkt, len)
   link.transmit(self.output.output, self.current_packet)
end

function L7Fw:push()
   local i       = assert(self.input.input, "input port not found")
   local o       = assert(self.output.output, "output port not found")
   local rules   = self.rules
   local scanner = self.scanner

   while not link.empty(i) do
      local pkt  = link.receive(i)
      local flow = scanner:get_flow(pkt)

      -- so that pfmatch handler methods can access the original packet
      self.current_packet = pkt

      if flow then
         local name   = scanner:protocol_name(flow.protocol)
         local policy = rules[name] or rules["default"]

         if policy == "accept" then
            self:accept(pkt.data, pkt.length)
         elseif policy == "drop" then
            self:drop(pkt.data, pkt.length)
         -- handle a pfmatch string case
         elseif type(policy) == "string" then
            if self.handler_map[policy] then
               -- we've already compiled a matcher for this policy
               self.handler_map[policy](self, pkt.data, pkt.length, flow.packets)
            else
               local opts    = { extra_args = { "flow_count" } }
               local handler = match.compile(policy, opts)
               self.handler_map[policy] = handler
               handler(self, pkt.data, pkt.length, flow.packets)
            end
         -- TODO: what should the default policy be if there is none specified?
         else
            self:accept(pkt.data, pkt.length)
         end
      else
         -- TODO: we may wish to have a default policy for packets
         --       without detected flows instead of just forwarding
         link.transmit(o, pkt)
      end
   end
end
