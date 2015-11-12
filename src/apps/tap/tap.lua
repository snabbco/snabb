module(..., package.seeall)

local S = require("syscall")
local link = require("core.link")
local packet = require("core.packet")
local ffi = require("ffi")
local C = ffi.C
local mac = require("lib.macaddress")
local const = require "syscall.linux.constants"

local t = S.types.t

Tap = { }

--- Where should this go?
local SIOCSIFHWADDR = 0x8924

function Tap:new (cfg)
   if type(cfg) == "string" then
      cfg = { name = cfg }
   end
   -- Are assertions the way to signal brokenness upwards?
   assert(cfg['name'], "missing tap interface name")
   
   local sock, err = S.open("/dev/net/tun", "rdwr, nonblock");
   assert(sock, "Error opening /dev/net/tun: " .. tostring(err))
   local ifr = t.ifreq()
   ifr.flags = "tap, no_pi"
   ifr.name = cfg['name']
   local ok, err = sock:ioctl("TUNSETIFF", ifr)
   if not ok then
      S.close(sock)
      assert(false, "Error opening /dev/net/tun: " .. tostring(err))
   end
   
   local obj = setmetatable({sock = sock}, {__index = Tap})
   
   if cfg['mac'] then
      obj:mac(cfg['mac'])
   end
   return obj
end

function Tap:mac (macaddr)
   local macaddr,err = mac:new(macaddr)
   assert(macaddr, tostring(err))

   local ifr = t.ifreq()
   ifr.ifr_ifru.ifru_hwaddr.sa_family = 1
   local m = ffi.cast('uint8_t*', ifr.ifr_ifru.ifru_hwaddr.sa_data)
   ffi.copy(m, macaddr.bytes, mac.ETHER_ADDR_LEN)
   local ok, err = self.sock:ioctl(SIOCSIFHWADDR, ifr)
   assert(ok, tostring("Failed to set mac address: " .. tostring(err)))
end

function Tap:pull ()
   local l = self.output.output
   if l == nil then return end
   while not link.full(l) do
      local p = packet.allocate()
      local len, err = S.read(self.sock, p.data, C.PACKET_PAYLOAD_SIZE)
      if not len and err.errno == const.E.AGAIN then 
         packet.free(p)
         return
      end
      if not len then
         -- How should this be bubbled up?
         assert(0, "something broke")
      end
      link.transmit(l, p)
   end
end

function Tap:push ()
   local l = self.input.input
   while not link.empty(l) do
      local p = link.front(l)
      local len, err = S.write(self.sock, p.data, p.length)
      if not len and err.errno ~= const.E.AGAIN or len and len ~= p.length then
         -- How should this be bubbled up?
         -- What does a partial write actually mean?
         assert(0, "something broke")
      end
      if len ~= p.length and err.errno == const.E.AGAIN then
         return
      end
      link.receive(l)
      packet.free(p)
   end
end

function Tap:stop()
   S.close(self.sock)
end

function selftest ()
   -- How should this be implemented. 
   -- Should it rely on RawSocket?
end
