module(...,package.seeall)

local buffer = require("core.buffer")
local freelist = require("core.freelist")
local lib = require("core.lib")
local packet = require("core.packet")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local g_ethernet = require("apps.fuzz.ethernet")
local g_ipv4 = require("apps.fuzz.ipv4")
local g_ipv6 = require("apps.fuzz.ipv6")
local g_udp = require("apps.fuzz.udp")
local g_tcp = require("apps.fuzz.tcp")

local ffi = require("ffi")
local C = ffi.C

local uint16_t_size = ffi.sizeof("uint16_t")

matcher = {}
matcher.__index = matcher

function matcher:new (data_list)
   return setmetatable({
      zone="matcher",
      data_list = data_list,
   }, matcher)
end

function matcher:get_mark(p)
   local iovec = p.iovecs[0]
   local b = iovec.buffer
   local offset = iovec.offset + iovec.length - uint16_t_size
   local pmark = ffi.cast("uint16_t*",b.pointer + offset)
   return C.ntohs(pmark[0])
end

function matcher:error(message)
   print("--------------------------------------------------------------------------------")
   print("[ERROR]"..message)
   print("--------------------------------------------------------------------------------")
   return
end

function matcher:match(p)

   -- squash all data in iovecs[0]
   packet.coalesce(p)

   local id = self:get_mark(p)
   local match = self.data_list[id]
   if not match then
      self:error("can not find a match for the packet\n"..packet.report(p))
      return
   end

   local iovec = p.iovecs[0]
   local ptr = iovec.buffer.pointer + iovec.offset
   local len = p.length
   local match_stack = match.dg:stack()

   if #match_stack > 0 then

      -- determine the parse list
      local d = datagram:new(p, ethernet)
      if not d:parse(match.match) then
         self:error("can not parse the packet\n"..packet.report(p))
      end

      local stack = d:stack()

      for k, header in ipairs(stack) do
         local match_header = match_stack[k]

         if not match_header then
            print("No match_header for "..tostring(k))
         end

         if not header then
            print("No header for "..tostring(k))
         end

         if match_header and header then
            if not match_header:eq(header) then
               self:error("can not match")
               return
            end
         end
      end
      -- update for payload compare
      ptr, len = d:payload()
   else
   -- raw packet
   end

   -- compare raw payload
   if ffi.string(match.dg:payload()) ~= ffi.string(ptr, len) then
      self:error("raw packet data does not match")
      return
   end

   -- if we got here, all checks passed and we'll increase the received counter
   match.received = match.received + 1
end

function matcher:report()
   local sent, received = 0,0
   for _,match in ipairs(self.data_list) do
      if match.received ~= #match.sg then
         print(string.format("Mismatch for packet %s. Generated %d, received %d.",
            match.desc, #match.sg, match.received))
      end
      sent = sent + #match.sg
      received = received + match.received
   end
   print(string.format("Sent:\t\t%d\nReceived:\t%d", sent, received))
end

return matcher
