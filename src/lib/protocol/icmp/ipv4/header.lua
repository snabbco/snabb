-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local icmp = subClass(require("lib.protocol.icmp.base"))

-- Class variables
icmp._ulp = {
   class_map = { [3]   = "lib.protocol.icmp.ipv4.destination_unreachable" },
   method    = "type" }

-- Override the base method to make sure that no pseudo header is used
-- for the checksum calculation.
function icmp:checksum (payload, length)
   icmp:superClass().checksum(self, payload, length)
end

return icmp
