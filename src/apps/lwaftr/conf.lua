module(..., package.seeall)

local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")

local bt = require("apps.lwaftr.binding_table")

DROP_POLICY = 1
DISCARD_PLUS_ICMP_POLICY = 2
DISCARD_PLUS_ICMPv6_POLICY = 3

local aftrconf = {
   aftr_ipv4_ip = ipv4:pton("10.10.10.10"),
   aftr_ipv6_ip = ipv6:pton('8:9:a:b:c:d:e:f'),
   aftr_mac_b4_side = ethernet:pton("22:22:22:22:22:22"),
   aftr_mac_inet_side = ethernet:pton("22:22:22:22:22:22"),
   b4_mac = ethernet:pton("44:44:44:44:44:44"),
   binding_table = bt.get_binding_table(),
   from_b4_lookup_failed_policy = DISCARD_PLUS_ICMPv6_POLICY,
   hairpinning = true,
   icmp_policy = DROP_POLICY,
   inet_mac = ethernet:pton("68:68:68:68:68:68"),
   ipv4_lookup_failed_policy = DISCARD_PLUS_ICMP_POLICY
}

function get_aftrconf()
   return aftrconf
end
