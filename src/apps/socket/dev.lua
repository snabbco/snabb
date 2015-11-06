module(..., package.seeall)

local S = require("syscall")
local h = require("syscall.helpers")
local packet = require("core.packet")
local bit = require("bit")
local ffi = require("ffi")
local C = ffi.C

local c, t = S.c, S.types.t

RawSocketDev = {}

function RawSocketDev:new (name)
   local tp = h.htons(c.ETH_P["ALL"])
   local sock, err = S.socket(c.AF.PACKET, bit.bor(c.SOCK.RAW, c.SOCK.NONBLOCK), tp)
   if not sock then return nil, err end
   local index, err = S.util.if_nametoindex(name, sock)
   if err then
      sock:close()
      return nil, err
   end
   local addr = t.sockaddr_ll{sll_family = c.AF.PACKET, sll_ifindex = index, sll_protocol = tp}
   local ok, err = S.bind(sock, addr)
   if not ok then
      S.close(sock)
      return nil, err
   end
   return setmetatable({sock = sock}, {__index = RawSocketDev})
end

function RawSocketDev:transmit (p)
   local _, err = S.write(self.sock, p.data, p.length)
   if err then return err; end
   return 0;
end

function RawSocketDev:can_transmit ()
   local ok, err = S.select({writefds = {self.sock}}, 0)
   return not (err or ok.count == 0)
end

function RawSocketDev:receive ()
   local p = packet.allocate()
   local ret, err = S.read(self.sock, p.data, C.PACKET_PAYLOAD_SIZE)
   if err then return err end
   p.length = ret
   return p
end

function RawSocketDev:can_receive ()
   local ok, err = S.select({readfds = {self.sock}}, 0)
   return not (err or ok.count == 0)
end

function RawSocketDev:stop ()
   S.close(self.sock)
end
