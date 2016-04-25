module(..., package.seeall)

local util = require("apps.wall.util")
local link = require("core.link")
local now  = require("core.app").now
local C    = require("ffi").C


L7Spy = setmetatable({}, util.SouthAndNorth)
L7Spy.__index = L7Spy

function L7Spy:new (s)
   if s.scanner == nil then
      s.scanner = "ndpi"
   end

   local scanner = s.scanner
   if type(scanner) == "string" then
      scanner = require("apps.wall.scanner." .. scanner):new()
   end

   return setmetatable({ scanner = scanner }, self)
end

function L7Spy:push ()
   self.time = now()
   self:push_northbound()
   self:push_southbound()
end

function L7Spy:on_southbound_packet (p)
   self.scanner:scan_packet(p, self.time)
   return p
end

L7Spy.on_northbound_packet = L7Spy.on_southbound_packet
