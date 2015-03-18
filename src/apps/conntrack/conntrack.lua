module(..., package.seeall)

local app = require("core.app")
local config = require("core.config")
local pcap = require("apps.pcap.pcap")
local link = require("core.link")
local packet = require("core.packet")
local bit = require("bit")

Conntrack = {}

local conns = {}
local conns_rev_ack = {}
local three_way_hand = {}

local new_conn_id = (function()
   local count = 0
   return function()
      count = count + 1
      return "conn_"..id
   end
end)()

function Conntrack:new(arg)
   self.packet_counter = 1
   return setmetatable({}, {__index = Conntrack})
end

function Conntrack:push()
   local i = assert(self.input.input, "input port not found")
   local o = assert(self.output.output, "output port not found")

   while not link.empty(i) and not link.full(o) do
      self:process_packet(i, o)
      self.packet_counter = self.packet_counter + 1
   end
end

local function add_connection(src, dst)
   if not conns[src] then
      conns[src] = {}
   end
   if not conns[src][dst] then
      conns[src][dst] = true 
   end
end 

local function count(hash)
   local result = 0
   for _, _ in pairs(hash) do
      result = result + 1
   end
   return result
end

local function uint32(a, b, c, d)
   return a * 2^24 + b * 2^16 + c * 2^8 + d
end

local function uint16(a, b)
   return a * 2^8 + b
end

local function ip_src(p)
   return uint32(p[26], p[27], p[28], p[29])
end

local function ip_str(a, b, c, d)
   return ("%d.%d.%d.%d"):format(a, b, c, d)
end

local function ip_src_str(p)
   return ip_str(p[26], p[27], p[28], p[29])
end

local function ip_dst(p)
   return uint32(p[30], p[31], p[32], p[33])
end

local function ip_dst_str(p)
   return ip_str(p[30], p[31], p[32], p[33])
end

local conn = {}

local function key(src, dst, offset)
   local result = tostring(src).."-"..tostring(dst)
   if offset then
      return result.."-"..offset
   end
   return result
end

local function protocol(p)
   return p[23]
end

local function is_proto(p, proto)
   return bit.band(p[23], proto)
end

local TCP = 0x06

local function tcpflags(p, flag)
   return bit.band(p[47], 0x3F) == flag
end

local function is_syn(p)
   return tcpflags(p, 0x02)
end

local function is_syn_ack(p)
   return tcpflags(p, bit.bor(0x02, 0x10))
end

local function is_ack(p)
   return tcpflags(p, 0x10)
end

local function src_port(p)
   return uint16(p[34], p[35])
end

local function dst_port(p)
   return uint16(p[36], p[37])
end

local function seq(p)
   return uint32(p[38], p[39], p[40], p[41])
end

local function ack(p)
   return uint32(p[42], p[43], p[44], p[45])
end

local function reserved(p)
   local w = uint16(p[46], p[47])
   return bit.band(w, 0x0FC0)
end

function Conntrack:process_packet(i, o)
   local p = link.receive(i)

   -- print("Before: "..count_connections())
   -- local src = ip_src(p.data)
   -- local dst = ip_dst(p.data)

   -- add_connection(src, dst)

   -- print(("src: %s; dst: %s"):format(src, dst))

   -- drop every other packet
   if self.packet_counter % 2 == 0 then
      local p = p.data

      local src = ip_src_str(p)
      local dst = ip_dst_str(p)
      local key = key(src, dst)

      local seq = seq(p)
      local ack = ack(p)

      -- print("src: "..src.."; dst: "..dst.."; src_port: "..src_port(p).."; dst_port: "..dst_port(p).."; proto: "..protocol(p))
      print("src: "..src.."; dst: "..dst.."; src_port: "..src_port(p).."; dst_port: "..dst_port(p).."; reserved: "..reserved(p))

      -- print("src: "..src.."; dst: "..dst.."; reserved: "..reserved(p))

      --[[
      if is_syn(p) then
         print("Is SYN! - src: "..src.."; dst: "..dst.."; seq: "..seq.."; ack: "..ack)
      end

      if is_ack(p) then
         print("Is SYN! - src: "..src.."; dst: "..dst.."; seq: "..seq.."; ack: "..ack)
      end
      --]]

      -- print("src: "..src.."; dst: "..dst.."; seq: "..seq.."; ack: "..ack)

      --[[
      if is_syn(p.data) then

      elseif is_syn(p.data) and is_ack(p.data)

      elseif is_ack(p.data) then

      end
      --]]

      --[[
      -- Only TCP packets with a successfully established connection
      if seq(p.data) == 0 and ack(p.data) == 0 then
         three_way_hand[key] = "syn"
      -- elseif seq(p.data) == 0 and ack(p.data) == 1 then
      elseif ack(p.data) == 0 then
         print("Switch to ack")
         assert(three_way_hand[key] == "syn", "Error: spoofing connection")
         three_way_hand[key] = "ack"
      elseif seq(p.data) == 1 and ack(p.data) == 1 then
         print("Switch to syn-ack")
         assert(three_way_hand[key] == "ack", "Error: spoofing connection")
         three_way_hand[key] = "syn-ack"

         local conn_id = new_conn_id()
         local seq = seq(p.data)
         local ack = ack(p.data)

         conns[conn_id] = { src = src, dst = dst, seq = seq, ack = ack }
         conns_rev_ack[key(src, dst, ack)] = conn_id
      else
         -- print("ack: "..ack(p.data))
         if three_way_hand[key] then
            -- print("src: "..ip_src_str(p.data).."; key: "..ip_dst_str(p.data).."; flag: "..three_way_hand[key])
         end
         -- assert(three_way_hand[key] == "syn-ack")

         -- local key = key(src, dst, seq(p.data))
         -- assert(conn_rev_ack[key], "Error: sequence number has not associated ACK")
         -- local conn_id = conn_rev_ack[key]
         -- conn_rev_ack[key] = nil
      end

      -- Once the connection is established:
      --    * Create a new entry in the table of connections.
      --    * This table stores the last sequence number.
      --    * Keep track of the connection number and associate each packet to its correspondent connection.

      link.transmit(o, p)
      --]]
   else
      packet.free(p)
   end

end
