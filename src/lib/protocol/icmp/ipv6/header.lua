-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local icmp = subClass(require("lib.protocol.icmp.base"))

-- Class variables
icmp._ulp = {
   class_map = { [2]   = "lib.protocol.icmp.ipv6.ptb",
                 [135] = "lib.protocol.icmp.ipv6.nd.ns",
                 [136] = "lib.protocol.icmp.ipv6.nd.na" },
   method    = "type" }

return icmp
