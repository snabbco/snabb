local scanner = require("apps.wall.scanner")
local const   = require("apps.wall.constants")
local opt     = require("apps.wall.scanner.ndpi_opt")
local util    = require("apps.wall.util")
local ndpi    = require("ndpi")

local rd32, ipv4_addr_cmp, ipv6_addr_cmp = util.rd32, util.ipv4_addr_cmp, util.ipv6_addr_cmp
local ETH_TYPE_IPv4  = const.ETH_TYPE_IPv4
local ETH_TYPE_IPv6  = const.ETH_TYPE_IPv6
local IPv4_PROTO_UDP = const.IPv4_PROTO_UDP
local IPv4_PROTO_TCP = const.IPv4_PROTO_TCP

local NdpiFlow = subClass()
NdpiFlow._name = "SnabbWall nDPI Flow"

function NdpiFlow:new(key)
   local f = NdpiFlow:superClass().new(self)
   f._ndpi_flow   = ndpi.flow()
   f._ndpi_src_id = ndpi.id()
   f._ndpi_dst_id = ndpi.id()
   f.protocol     = ndpi.protocol.PROTOCOL_UNKNOWN
   f.proto_master = ndpi.protocol.PROTOCOL_UNKNOWN
   f.key          = key
   f.packets      = 0
   f.last_seen    = 0
   return f
end

function NdpiFlow:update_counters(time)
   self.packets = self.packets + 1
   self.last_seen = time
end

local NdpiScanner = subClass(scanner.Scanner)
NdpiScanner._name = "SnabbWall nDPI packet Scanner"

function NdpiScanner:new(ticks_per_second)
   local s = NdpiScanner:superClass().new(self)
   s.protocols = ndpi.protocol_bitmask():set_all()
   s._ndpi     = ndpi.detection_module(ticks_per_second or 1000):set_protocol_bitmask(s.protocols)
   s._flows    = {}
   return s
end


function NdpiScanner:get_flow(p)
   local key = (self:extract_packet_info(p))
   return key and self._flows[key:hash()] or nil
end

function NdpiScanner:flows()
   local flows = self._flows
   return coroutine.wrap(function ()
      for _, flow in pairs(flows) do
         coroutine.yield(flow)
      end
   end)
end

function NdpiScanner:protocol_name(protocol)
   local name = ndpi.protocol[protocol]
   if name:sub(1, #"PROTOCOL_") == "PROTOCOL_" then
      name = name:sub(#"PROTOCOL_" + 1)
   end
   return name
end

-- FIXME: Overall this needs checking for packet boundaries and sizes
function NdpiScanner:scan_packet(p, time)
   -- Extract packet information
   local key, ip_offset, src_addr, src_port, dst_addr, dst_port = self:extract_packet_info(p)
   if not key then
      return false, nil
   end

   -- Get an existing data flow or create a new one
   local key_hash = key:hash()
   local flow = self._flows[key_hash]
   if not flow then
      flow = NdpiFlow:new(key)
      self._flows[key_hash] = flow
   end

   flow:update_counters(time)
   if flow.protocol ~= ndpi.protocol.PROTOCOL_UNKNOWN then
      return true, flow
   end

   local src_id, dst_id = flow._ndpi_src_id, flow._ndpi_dst_id
   if key:eth_type() == ETH_TYPE_IPv4 then
      if ipv4_addr_cmp(src_addr, key.lo_addr) ~= 0 or
         ipv4_addr_cmp(dst_addr, key.hi_addr) ~= 0 or
         src_port ~= key.lo_port or dst_port ~= key.hi_port
      then
         src_id, dst_id = dst_id, src_id
      end
   elseif key:eth_type() == ETH_TYPE_IPv6 then
      if ipv6_addr_cmp(src_addr, key.lo_addr) ~= 0 or
         ipv6_addr_cmp(dst_addr, key.hi_addr) ~= 0 or
         src_port ~= key.lo_port or dst_port ~= key.hi_port
      then
         src_id, dst_id = dst_id, src_id
      end
   end

   flow.proto_master, flow.protocol =
         opt.process_packet(self._ndpi,
                            flow._ndpi_flow,
                            p.data + ip_offset,
                            p.length - ip_offset,
                            time,
                            src_id,
                            dst_id)

   if flow.protocol ~= ndpi.protocol.PROTOCOL_UNKNOWN then
      return true, flow
   end

   -- TODO: Check and tune-up the constants for number of packets
   -- TODO: Do similarly for IPv6 packets once nDPI supports using IPv6
   --       addresses here (see https://github.com/ntop/nDPI/issues/183)
   if (flow.key.ip_proto == IPv4_PROTO_UDP and flow.packets > 8) or
      (flow.key.ip_proto == IPv4_PROTO_TCP and flow.packets > 10)
   then
      flow.proto_master, flow.protocol =
            opt.guess_undetected_protocol(self._ndpi,
                                          flow.key.ip_proto,
                                          rd32(src_addr), src_port,
                                          rd32(dst_addr), dst_port)
      -- TODO: Check whether we should check again for PROTOCOL_UNKNOWN
      return true, flow
   end

   -- Flow not yet identified
   return false, flow
end

return NdpiScanner
