module(..., package.seeall)

local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")

local bt = require("apps.lwaftr.binding_table")

DROP_POLICY = 1


local aftrconf = {
   aftr_ipv6_ip = ipv6:pton('8:9:a:b:c:d:e:f'),
   aftr_mac = ethernet:pton("22:22:22:22:22:22"),
   binding_table = bt.get_binding_table(),
   icmp_policy = DROP_POLICY
}

function get_aftrconf()
   return aftrconf
end
