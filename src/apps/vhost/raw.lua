module(...,package.seeall)

local vhost = require("apps.vhost.vhost")
local TapVhost = require("apps.vhost.vhost_apps").TapVhost

RawVhost = {}
setmetatable(RawVhost, { __index = TapVhost })

function RawVhost:new (ifname)
   local dev = vhost.new(ifname, "raw")
   return setmetatable({ dev = dev }, {__index = RawVhost})
end

function RawVhost.selftest ()
   print("lib.vhost.raw selftest not implemented")
end

return RawVhost
