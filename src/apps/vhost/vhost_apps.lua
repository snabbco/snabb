module(...,package.seeall)

local app    = require("core.app")
local config = require("core.config")
local link   = require("core.link")
local packet = require("core.packet")
local lib    = require("core.lib")
local vhost  = require("apps.vhost.vhost")
local basic_apps = require("apps.basic.basic_apps")

local skip_selftest = true

TapVhost = {}

function TapVhost:new (ifname)
   local dev = vhost.new(ifname)
   return setmetatable({ dev = dev }, {__index = TapVhost})
end

function TapVhost:pull ()
   self.dev:sync_receive()
   self.dev:sync_transmit()
   local l = self.output.tx
   if l == nil then return end
   while not link.full(l) and self.dev:can_receive() do
      link.transmit(l, self.dev:receive())
   end
   while self.dev:can_add_receive_buffer() do
      self.dev:add_receive_buffer(buffer.allocate())
   end
end

function TapVhost:push ()
   local l = self.input.rx
   if l == nil then return end
   while not link.empty(l) and self.dev:can_transmit() do
      local p = link.receive(l)
      self.dev:transmit(p)
      packet.deref(p)
   end
end

function selftest ()
   if skip_selftest or not vhost.is_tuntap_available() then
      print("/dev/net/tun absent or not avaiable\nTest skipped")
      os.exit(app.test_skipped_code)
   end

   local c = config.new()
   config.app(c, "source", basic_apps.Source)
   config.app(c, "tapvhost", TapVhost, "snabb%d")
   config.app(c, "sink", basic_apps.Sink)
   config.link(c, "source.out -> tapvhost.rx")
   config.link(c, "tapvhost.tx -> sink.in")
   app.configure(c)
   buffer.preallocate(100000)
   app.main({duration = 1})
end

