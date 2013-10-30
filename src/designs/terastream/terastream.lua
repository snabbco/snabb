module(...,package.seeall)

local app        = require("core.app")
local vhost_apps = require("apps.vhost.vhost_apps")
local basic_apps = require("apps.basic.basic_apps")
local vhost      = require("apps.vhost.vhost")
local ipv6       = require("apps.ipv6.ipv6")
local lib        = require("core.lib")

function main ()
   app.apps.tap = app.new(vhost_apps.TapVhost:new("snabb%d"))
   app.apps.ipv6 = app.new(ipv6.SimpleIPv6:new())
   app.connect("tap", "tx",      "ipv6", "snabb0")
   app.connect("ipv6", "snabb0", "tap", "rx")
   app.relink()
   local deadline = lib.timer(100e9)
   repeat app.breathe() until deadline()
   app.report()
end

main()

