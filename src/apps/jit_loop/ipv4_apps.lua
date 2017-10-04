module(..., package.seeall)

local ethernet = require("lib.protocol.ethernet")
local receive, transmit = link.receive, link.transmit
local lpm4     = require("lib.lpm.lpm4_trie").LPM4_trie
local ipv4     = require("lib.protocol.ipv4")

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

RouteNorth = {}
local IP_TYPE     = 0x0800
local ARP_TYPE    = 0x0806
local IPICMP_TYPE = 0x01
local ETH_SIZE    = ethernet:sizeof() 

function RouteNorth:new (conf)
   local o = {lpm_hash  = lpm4:new(),
              arp_table = {},
              src_eth   = ethernet:pton(conf.src_eth),
              eth_pkt   = ethernet:new({}),
              ippkt     = ipv4:new({})}
   o.lpm_hash:add_string("16.0.0.1/24", 1)
   o.lpm_hash:build()
   o.arp_table[1] = ethernet:pton("08:35:71:00:97:14")
   return setmetatable(o, {__index = self})
end

function RouteNorth:push()
  local i = assert(self.input.input, "input port not found")
  local o = assert(self.output.output, "output port not found")

  while not link.empty(i) do
     local p = link.receive(i)
     local result = self:process_packet(p, o)
  end
end

function RouteNorth:process_packet(p, o)
  local eth_pkt = self.eth_pkt:new_from_mem(p.data, p.length)
  if eth_pkt:type() == IP_TYPE then
     local ippkt = self.ippkt:new_from_mem(p.data+ETH_SIZE, ipv4:sizeof())
     if ippkt:protocol() == IPICMP_TYPE then
        packet.free(p)
     end
     local client_ip = ippkt:dst()
     local gw_idx = self.lpm_hash:search_string(ipv4:ntop(client_ip))
     if gw_idx == nil then
        logger:log("Freeing a packet as index is nil")
        packet.free(p)
     else
        local lookedup_mac = self.arp_table[gw_idx]
        eth_pkt:src(self.src_eth)
        eth_pkt:dst(lookedup_mac)
        link.transmit(o,p)
     end
  else
     packet.free(p)
  end
end
