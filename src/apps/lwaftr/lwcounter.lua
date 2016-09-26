module(..., package.seeall)

local counter = require("core.counter")
local shm = require("core.shm")

-- COUNTERS
-- The lwAFTR counters all live in the same directory, and their filenames are
-- built out of ordered field values, separated by dashes.
-- Fields:
-- - "memuse", or direction: "in", "out", "hairpin", "drop";
-- If "direction" is "drop":
--   - reason: reasons for dropping;
-- - protocol+version: "icmpv4", "icmpv6", "ipv4", "ipv6";
-- - size: "bytes", "packets".
counters_dir = "apps/lwaftr/"
-- Referenced by program/check/check.lua
counter_names = {

-- All incoming traffic.
   "in-ipv4-bytes",
   "in-ipv4-packets",
   "in-ipv6-bytes",
   "in-ipv6-packets",

-- Outgoing traffic, not including internally generated ICMP error packets.
   "out-ipv4-bytes",
   "out-ipv4-packets",
   "out-ipv6-bytes",
   "out-ipv6-packets",

-- Internally generated ICMP error packets.
   "out-icmpv4-bytes",
   "out-icmpv4-packets",
   "out-icmpv6-bytes",
   "out-icmpv6-packets",

-- Hairpinned traffic.
   "hairpin-ipv4-bytes",
   "hairpin-ipv4-packets",

-- Dropped v4 traffic.

-- All dropped traffic on the IPv4 interface.
   "drop-all-ipv4-iface-bytes",
   "drop-all-ipv4-iface-packets",
-- On IPv4 link, but not IPv4.
   "drop-misplaced-not-ipv4-bytes",
   "drop-misplaced-not-ipv4-packets",
-- No matching destination softwire.
   "drop-no-dest-softwire-ipv4-bytes",
   "drop-no-dest-softwire-ipv4-packets",
-- TTL is zero.
   "drop-ttl-zero-ipv4-bytes",
   "drop-ttl-zero-ipv4-packets",
-- Big packets exceeding MTU, but DF (Don't Fragment) flag set.
   "drop-over-mtu-but-dont-fragment-ipv4-bytes",
   "drop-over-mtu-but-dont-fragment-ipv4-packets",
-- Bad checksum on ICMPv4 packets.
   "drop-bad-checksum-icmpv4-bytes",
   "drop-bad-checksum-icmpv4-packets",
-- Incoming ICMPv4 packets with no destination (RFC 7596 section 8.1)
   "drop-in-by-rfc7596-icmpv4-bytes",
   "drop-in-by-rfc7596-icmpv4-packets",
-- Policy of dropping incoming ICMPv4 packets.
   "drop-in-by-policy-icmpv4-bytes",
   "drop-in-by-policy-icmpv4-packets",
-- Policy of dropping outgoing ICMPv4 error packets.
-- Not counting bytes because we do not even generate the packets.
   "drop-out-by-policy-icmpv4-packets",

-- Drop v6.

-- All dropped traffic on the IPv4 interface.
   "drop-all-ipv6-iface-bytes",
   "drop-all-ipv6-iface-packets",
-- On IPv6 link, but not IPv6.
   "drop-misplaced-not-ipv6-bytes",
   "drop-misplaced-not-ipv6-packets",
-- Unknown IPv6 protocol.
   "drop-unknown-protocol-ipv6-bytes",
   "drop-unknown-protocol-ipv6-packets",
-- No matching source softwire.
   "drop-no-source-softwire-ipv6-bytes",
   "drop-no-source-softwire-ipv6-packets",
-- Unknown ICMPv6 type.
   "drop-unknown-protocol-icmpv6-bytes",
   "drop-unknown-protocol-icmpv6-packets",
-- "Packet too big" ICMPv6 type but not code.
   "drop-too-big-type-but-not-code-icmpv6-bytes",
   "drop-too-big-type-but-not-code-icmpv6-packets",
-- Time-limit-exceeded, but not hop limit on ICMPv6 packet.
   "drop-over-time-but-not-hop-limit-icmpv6-bytes",
   "drop-over-time-but-not-hop-limit-icmpv6-packets",
-- Drop outgoing ICMPv6 error packets because of rate limit reached.
   "drop-over-rate-limit-icmpv6-bytes",
   "drop-over-rate-limit-icmpv6-packets",
-- Policy of dropping incoming ICMPv6 packets.
   "drop-in-by-policy-icmpv6-bytes",
   "drop-in-by-policy-icmpv6-packets",
-- Policy of dropping outgoing ICMPv6 error packets.
-- Not counting bytes because we do not even generate the packets.
   "drop-out-by-policy-icmpv6-packets",

-- Reassembly counters
   "in-ipv4-frag-needs-reassembly",
   "in-ipv4-frag-reassembled",
   "in-ipv4-frag-reassembly-unneeded",
   "drop-ipv4-frag-disabled",
   "drop-ipv4-frag-invalid-reassembly",
   "drop-ipv4-frag-random-evicted",
   "out-ipv4-frag",
   "out-ipv4-frag-not",
   "memuse-ipv4-frag-reassembly-buffer",

   "in-ipv6-frag-needs-reassembly",
   "in-ipv6-frag-reassembled",
   "in-ipv6-frag-reassembly-unneeded",
   "drop-ipv6-frag-disabled",
   "drop-ipv6-frag-invalid-reassembly",
   "drop-ipv6-frag-random-evicted",
   "out-ipv6-frag",
   "out-ipv6-frag-not",
   "memuse-ipv6-frag-reassembly-buffer",

-- Ingress packet drops
   "ingress-packet-drops",
}

function init_counters ()
   local counters = {}
   for _, name in ipairs(counter_names) do
      counters[name] = {counter}
   end
   return shm.create_frame(counters_dir, counters)
end
