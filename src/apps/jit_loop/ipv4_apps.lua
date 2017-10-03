module(..., package.seeall)

local ethernet = require("lib.protocol.ethernet")
local receive, transmit = link.receive, link.transmit

ChangeMAC = {}

function ChangeMAC:new(conf)
   local o = setmetatable({}, {__index=ChangeMAC})
   o.conf = conf
   o.src_eth       = ethernet:pton(conf.src_eth)
   o.dst_eth       = ethernet:pton(conf.dst_eth)
   o.eth_pkt       = ethernet:new({})
   return o
end

function ChangeMAC:push()
   local i, o = self.input.input, self.output.output
   for _ = 1, link.nreadable(i) do
      local p = receive(i)
      local data, length = p.data, p.length
      if length > 0 then
         local eth_pkt = self.eth_pkt:new_from_mem(data, length)
         eth_pkt:src(self.src_eth)
         eth_pkt:dst(self.dst_eth)
         transmit(o, p)
      else
         packet.free(p)
      end
   end
end
