module(..., package.seeall)

local app = require("core.app")
local config = require("core.config")
local pcap = require("apps.pcap.pcap")
local link = require("core.link")
local packet = require("core.packet")
local bit = require("bit")

Conntrack = {}

local new_conn_id = (function()
   local count = 0
   return function()
      count = count + 1
      return "conn_"..count
   end
end)()

function Conntrack:new(arg)
   self.packet_counter = 1
   self.conns = {}   
   self.conn_packs = {}
   self.three_way_handshake = {}
   return setmetatable({}, {__index = Conntrack, 
      __gc = function() print("__gc") end })
end

function Conntrack:destroy()
   print("Destroy!!")
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

-- IP

local function length(p)
   return uint16(p[16], p[17])   
end

local function src_ip(p)
   return uint32(p[26], p[27], p[28], p[29])
end

local function ip_str(a, b, c, d)
   return ("%d.%d.%d.%d"):format(a, b, c, d)
end

local function src_ip_str(p)
   return ip_str(p[26], p[27], p[28], p[29])
end

local function dst_ip(p)
   return uint32(p[30], p[31], p[32], p[33])
end

local function dst_ip_str(p)
   return ip_str(p[30], p[31], p[32], p[33])
end

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

-- TCP

local TCP = 0x06

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

-- TCP_FLAGS

local TCP_SYN     = 0x02
local TCP_ACK     = 0x10
local TCP_SYN_ACK = 0x12
local TCP_FIN     = 0x20

local function tcpflags(p, flag)
   return bit.band(p[47], 0x3F) == flag
end

-- TCP connection negotiation

local function packet_id(p)
   local src = src_ip_str(p)..":"..src_port(p)
   local dst = dst_ip_str(p)..":"..dst_port(p)
   return src.."-"..dst
end

local function is_syn(p)
   return tcpflags(p, TCP_SYN)
end

local function is_ack(p)
   return tcpflags(p, TCP_ACK)
end

local function is_syn_ack(p)
   return tcpflags(p, TCP_SYN_ACK)
end

local function is_fin(p)
   return tcpflags(p, TCP_FIN)
end

function Conntrack:process_packet(i, o)
   local p = link.receive(i)
   link.transmit(o, p)

   local p = p.data

   -- A packet id is defined by the tuple { src_ip; src_port; dst_ip; dst_port }
   local p_id = packet_id(p) 

   if self.three_way_handshake[p_id] then
      if is_syn_ack(p) then
         if (self.three_way_handshake[p_id] == ack(p)) then
            self.three_way_handshake[p_id] = seq(p) + 1
            return
         end
      end
      if is_ack(p) then
         if (self.three_way_handshake[p_id] == seq(p)) then
            -- The connection was established, create a new connection indexed by id
            local conn_id = new_conn_id()
            self.conns[p_id] = conn_id
            self.conn_packs[conn_id] = 0

            self.three_way_handshake[p_id] = nil
            return
         end
      end
      if is_fin(p) then
         self.three_way_handshake[p_id] = nil
         print("Destroyed connection: "..p_id)
         return
      end
   end

   -- Is SYN
   if is_syn(p) then
      self.three_way_handshake[p_id] = seq(p) + 1
      return
   end

   if self.conns[p_id] then
      conn_id = self.conns[p_id]
      self.conn_packs[conn_id] = self.conn_packs[conn_id] + 1
      -- print(conn_id..": "..self.conn_packs[conn_id])
   end

end
