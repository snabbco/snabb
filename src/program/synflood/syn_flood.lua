-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local ffi = require("ffi")
local ethernet = require("lib.protocol.ethernet")
local tcp      = require("lib.protocol.tcp")
local ip       = require("lib.protocol.ipv4")
local C = ffi.C
local datagram = require("lib.protocol.datagram")
local transmit, receive = link.transmit, link.receive
local lib = require("core.lib")
local htons, ntohs, htonl, ntohl =
   lib.htons, lib.ntohs, lib.htonl, lib.ntohl

ip_mod = {}

function ip_mod:new(ip_conf)
   ip_conf.curr = ip_conf.start
   return setmetatable(ip_conf, {__index = ip_mod})
end


function split(s, p)
    local rt= {}
    string.gsub(s, '[^'..p..']+', function(w) table.insert(rt, w) end )
    return rt
end


function ip_mod:inc()	
   local ret = 0
   if self.curr == self.stop then
      self.curr = self.start
      ret = 1    
      return ret
   end

   local v = split(self.curr, '.')
   local i = 4 
   while i > 0 do
      local tail = tonumber(v[i])
      if tail +1 == 255 and i == 4 then
         v[i] = tostring(1)
      elseif tail +1 > 255 and i ~= 4 then
         v[i] = tostring(0)
      else
         v[i] = tostring(tail +1)
         break
      end
      i = i - 1
   end
   self.curr = table.concat(v, '.')
   return ret
end

port_mod = {}

function port_mod:new(port)
   port.curr = port.start
   return setmetatable(port, {__index = port_mod})
end


function port_mod:inc()
   self.curr = self.curr + 1
   local ret = 0
   if self.curr >= self.stop then
      self.curr = self.start
      ret = 1
   end 
   return ret
end

f_moder = {}

function f_moder:new(conf)
   conf[1] = conf.ip_src
   conf[2] = conf.ip_dst
   conf[3] = conf.sport
   conf[4] = conf.dport
   return setmetatable(conf, {__index = f_moder})
end

function f_moder:inc()
   local next_to_inc = 1
   local ret = 0
   repeat
      ret = self[next_to_inc]:inc()
      if ret == 1 then
         next_to_inc = next_to_inc + 1
      end
      if next_to_inc > 4 then
         next_to_inc = 1
      end
   until ret == 0  
end


Synfld = {}

local eth_src_addr = ethernet:pton("6c:92:bf:04:ee:92")
local eth_dst_addr = ethernet:pton("3c:8c:40:b0:27:a2")

config = {
      size    = 64,
      eth_src = eth_src_addr,
      eth_dst = eth_dst_addr, 
      mod_fields = f_moder:new({
         ip_src = ip_mod:new({ 
           start = '117.161.3.75',
           stop =  '117.161.3.78',
         }),

         ip_dst = ip_mod:new({
           start = '117.161.3.65',
           stop = '117.161.3.65',
         }),

         sport = port_mod:new({
           start = 1,
           stop = 65534,
         }), 

         dport = port_mod:new({ 
           start = 80,
           stop = 80,
         }),

         }),
}


function Synfld:new (conf)
   local payload_size = conf.size - ethernet:sizeof() - ip:sizeof() - tcp:sizeof() 
   assert(payload_size >= 0 and payload_size <= 1536,
         "Invalid payload size: "..payload_size)
   return setmetatable({conf=conf, done = false}, {__index=Synfld})
end

function Synfld:pull ()
      local n = 0
      while n < engine.pull_npackets do
         local payload_size = self.conf.size - ethernet:sizeof() - ip:sizeof() - tcp:sizeof()  
         local data = ffi.new("char[?]", payload_size)
         local dgram = datagram:new(packet.from_pointer(data, payload_size))
         local ether_hdr = ethernet:new({src = self.conf.eth_src,
                                      dst = self.conf.eth_dst,
                                      type = 0x0800 })
         local ip_hdr   = ip:new({src = ip:pton(self.conf.mod_fields.ip_src.curr), 
                                    dst = ip:pton(self.conf.mod_fields.ip_dst.curr),
                                    ttl = 64,
			            id = math.random(10000),
                                    protocol = 0x6})

         local tcp_hdr  = tcp:new({src_port = self.conf.mod_fields.sport.curr,
                                     dst_port = self.conf.mod_fields.dport.curr, 
                                     syn = 1,
                                     seq_num = math.random(100000),
                                     ack_num = math.random(100000),
                                     window_size = 512,
				     offset = tcp:sizeof() /4,
                                     })

	     ip_hdr:total_length(ip_hdr:total_length() + tcp_hdr:sizeof() + payload_size)
         ip_hdr:checksum()
         tcp_hdr:checksum(data, payload_size, ip_hdr)
         

         dgram:push(tcp_hdr)
         dgram:push(ip_hdr)
         dgram:push(ether_hdr)

         transmit(self.output.output, dgram:packet())

         self.conf.mod_fields:inc()
         n = n + 1
       end
end

function Synfld:stop ()
   
end

function selftest ()

end
