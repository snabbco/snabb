module(...,package.seeall)

local app = require("core.app")
local basic_apps = require("apps.basic.basic_apps")
local buffer = require("core.buffer")
local freelist = require("core.freelist")
local generator = require("apps.fuzz.generator")
local matcher = require("apps.fuzz.matcher")
local lib = require("core.lib")
local packet = require("core.packet")
local datagram = require("lib.protocol.datagram")

local link = require("core.link")

local ffi = require("ffi")
local C = ffi.C

fuzz = {}
fuzz.__index = fuzz

function fuzz:new ()
   generated = generator:new():generate()
   return setmetatable({
      zone="fuzz",
      generated = generated, -- all generated packets
      matcher = matcher:new(generated),
      sent = 0
   }, fuzz)
end

-- Allocate receive buffers from the given freelist.
function fuzz:set_rx_buffer_freelist (fl)
   assert(fl)
   self.rx_buffer_freelist = fl
end

function fuzz:get_next()
   self.sent = self.sent + 1
   return self.generated[self.sent]
end

function fuzz:receive(p)
   -- send the received packet to the matcher
   self.matcher:match(p)
   packet.deref(p)
end

function fuzz:pull ()
   local l = self.output.tx
   if l == nil then return end
   local d = self:get_next()
   if d then
      for _,p in ipairs(d.sg) do
         --print(packet.report(p))
         packet.ref(p) -- ensure enough refs
         link.transmit(l, p)
      end
   end
end

function fuzz:push ()
   local l = self.input.rx
   if l == nil then return end
   while not link.empty(l) do
      local p = link.receive(l)
      self:receive(p)
      packet.deref(p)
   end
end

function fuzz:report()
   self.matcher:report()
end

function selftest ()
   buffer.preallocate(100000)

   local c = config.new()
   config.app(c, 'fuzz', fuzz)
   config.app(c, 'tee', basic_apps.Tee)
   config.link(c, 'fuzz.tx -> tee.in')
   config.link(c, 'tee.out -> fuzz.rx')
   engine.configure(c)

   local fuzz = app.app_table.fuzz
   engine.main({duration = 1, report={showlinks=true, showapps=false}})
   fuzz:report()
end
