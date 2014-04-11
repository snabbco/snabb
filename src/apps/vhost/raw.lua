module(...,package.seeall)

local vhost = require("apps.vhost.vhost")
local TapVhost = require("apps.vhost.vhost_apps").TapVhost

RawVhost = TapVhost:new()

function RawVhost:open (ifname)
   assert(ifname)
   self.dev = vhost.new(ifname, "raw")
   return self
end

function selftest ()
   print("RawVhost selftest not implemented")
end

