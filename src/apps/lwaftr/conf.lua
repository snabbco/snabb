module(..., package.seeall)

local ipv6 = require("lib.protocol.ipv6")

local bt = require("apps.lwaftr.binding_table")

local aftrconf = {
   aftr_ipv6_ip = ipv6:pton('8:9:a:b:c:d:e:f'),
   binding_table = bt.get_binding_table()
}

function get_aftrconf()
   return aftrconf
end
