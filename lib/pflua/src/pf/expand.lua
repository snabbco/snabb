module(...,package.seeall)

local utils = require('pf.utils')

local verbose = os.getenv("PF_VERBOSE");

local expand_arith, expand_relop, expand_bool

local set, concat, pp = utils.set, utils.concat, utils.pp
local uint16, uint32 = utils.uint16, utils.uint32
local ipv4_to_int, ipv6_as_4x32 = utils.ipv4_to_int, utils.ipv6_as_4x32

local llc_types = set(
   'i', 's', 'u', 'rr', 'rnr', 'rej', 'ui', 'ua',
   'disc', 'sabme', 'test', 'xis', 'frmr'
)

local pf_reasons = set(
   'match', 'bad-offset', 'fragment', 'short', 'normalize', 'memory'
)

local pf_actions = set(
   'pass', 'block', 'nat', 'rdr', 'binat', 'scrub'
)

local wlan_frame_types = set('mgt', 'ctl', 'data')
local wlan_frame_mgt_subtypes = set(
   'assoc-req', 'assoc-resp', 'reassoc-req', 'reassoc-resp',
   'probe-req', 'probe-resp', 'beacon', 'atim', 'disassoc', 'auth', 'deauth'
)
local wlan_frame_ctl_subtypes = set(
   'ps-poll', 'rts', 'cts', 'ack', 'cf-end', 'cf-end-ack'
)
local wlan_frame_data_subtypes = set(
   'data', 'data-cf-ack', 'data-cf-poll', 'data-cf-ack-poll', 'null',
   'cf-ack', 'cf-poll', 'cf-ack-poll', 'qos-data', 'qos-data-cf-ack',
   'qos-data-cf-poll', 'qos-data-cf-ack-poll', 'qos', 'qos-cf-poll',
   'quos-cf-ack-poll'
)

local wlan_directions = set('nods', 'tods', 'fromds', 'dstods')

local function unimplemented(expr, dlt)
   error("not implemented: "..expr[1])
end

-- Ethernet protocols
local PROTO_AARP    = 33011 -- 0x80f3
local PROTO_ARP     = 2054  -- 0x806
local PROTO_ATALK   = 32923 -- 0x809b
local PROTO_DECNET  = 24579 -- 0x6003
local PROTO_IPV4    = 2048  -- 0x800
local PROTO_IPV6    = 34525 -- 0x86dd
local PROTO_IPX     = 33079 -- 0X8137
local PROTO_ISO     = 65278 -- 0xfefe
local PROTO_LAT     = 24580 -- 0x6004
local PROTO_MOPDL   = 24577 -- 0x6001
local PROTO_MOPRC   = 24578 -- 0x6002
local PROTO_NETBEUI = 61680 -- 0xf0f0
local PROTO_RARP    = 32821 -- 0x8035
local PROTO_SCA     = 24583 -- 0x6007
local PROTO_STP     = 66    -- 0x42

local ether_min_payloads = {
   [PROTO_IPV4] = 20,
   [PROTO_ARP]  = 28,
   [PROTO_RARP] = 28,
   [PROTO_IPV6] = 40
}

-- IP protocols
local PROTO_AH    = 51  -- 0x33
local PROTO_ESP   = 50  -- 0x32
local PROTO_ICMP  = 1   -- 0x1
local PROTO_ICMP6 = 58  -- 0x3a
local PROTO_IGMP  = 2   -- 0x2
local PROTO_IGRP  = 9   -- 0x9
local PROTO_PIM   = 103 -- 0x67
local PROTO_SCTP  = 132 -- 0x84
local PROTO_TCP   = 6   -- 0x6
local PROTO_UDP   = 17  -- 0x11
local PROTO_VRRP  = 112 -- 0x70

local ip_min_payloads = {
   [PROTO_ICMP] = 8,
   [PROTO_UDP]  = 8,
   [PROTO_TCP]  = 20,
   [PROTO_IGMP] = 8,
   [PROTO_IGRP] = 8,
   [PROTO_PIM]  = 4,
   [PROTO_SCTP] = 12,
   [PROTO_VRRP] = 8
}

-- ISO protocols

local PROTO_CLNP = 129        -- 0x81
local PROTO_ESIS = 130        -- 0x82
local PROTO_ISIS = 131        -- 0x83

local ETHER_TYPE       = 12
local ETHER_PAYLOAD    = 14
local IP_FLAGS         = 6
local IP_PROTOCOL      = 9

-- Minimum payload checks insert a byte access to the last byte of the
-- minimum payload size.  Since the comparison should fold (because it
-- will always be >= 0), we will be left with just an eager assertion on
-- the minimum packet size, which should help elide future packet size
-- assertions.
local function has_proto_min_payload(min_payloads, proto, accessor)
   local min_payload = assert(min_payloads[proto])
   return { '<=', 0, { accessor, min_payload - 1, 1 } }
end

-- When proto is greater than 1500 (0x5DC) , the frame is treated as an
-- Ethernet frame and the Type/Length is interpreted as Type, storing the
-- EtherType value.
-- Otherwise, the frame is interpreted as an 802.3 frame and the
-- Type/Length field is interpreted as Length. The Length cannot be greater
-- than 1500. The first byte after the Type/Length field stores the Service
-- Access Point of the 802.3 frame. It works as an EtherType at LLC level.
--
-- See: https://tools.ietf.org/html/draft-ietf-isis-ext-eth-01

local ETHER_MAX_LEN = 1500

local function has_ether_protocol(proto)
   if proto > ETHER_MAX_LEN then 
      return { '=', { '[ether]', ETHER_TYPE, 2 }, proto }
   end
   return { 'and',
            { '<=', {'[ether]', ETHER_TYPE, 2}, ETHER_MAX_LEN },
            { '=', { '[ether]', ETHER_PAYLOAD, 1}, proto } }
end
local function has_ether_protocol_min_payload(proto)
   return has_proto_min_payload(ether_min_payloads, proto, '[ether*]')
end
local function has_ipv4_protocol(proto)
   return { '=', { '[ip]', IP_PROTOCOL, 1 }, proto }
end
local function has_ipv4_protocol_min_payload(proto)
   -- Since the [ip*] accessor asserts that is_first_ipv4_fragment(),
   -- and we don't want that, we use [ip] and assume the minimum IP
   -- header size.
   local min_payload = assert(ip_min_payloads[proto])
   min_payload = min_payload + assert(ether_min_payloads[PROTO_IPV4])
   return { '<=', 0, { '[ip]', min_payload - 1, 1 } }
end

local function is_first_ipv4_fragment()
   return { '=', { '&', { '[ip]', IP_FLAGS, 2 }, 0x1fff }, 0 }
end
local function has_ipv6_protocol(proto)
   local IPV6_NEXT_HEADER_1 = 6
   local IPV6_NEXT_HEADER_2 = 40
   local IPV6_FRAGMENTATION_EXTENSION_HEADER = 44
   return { 'and', { 'ip6' },
            { 'or',
              { '=', { '[ip6]', IPV6_NEXT_HEADER_1, 1 }, proto },
              { 'and',
                { '=', { '[ip6]', IPV6_NEXT_HEADER_1, 1 },
                  IPV6_FRAGMENTATION_EXTENSION_HEADER },
                { '=', { '[ip6]', IPV6_NEXT_HEADER_2, 1 }, proto } } } }
end
local function has_ipv6_protocol_min_payload(proto)
   -- Assume the minimum ipv6 header size.
   local min_payload = assert(ip_min_payloads[proto])
   min_payload = min_payload + assert(ether_min_payloads[PROTO_IPV6])
   return { '<=', 0, { '[ip6]', min_payload - 1, 1 } }
end
local function has_ip_protocol(proto)
   return { 'if', { 'ip' }, has_ipv4_protocol(proto), has_ipv6_protocol(proto) }
end

-- Port operations
--

local SRC_PORT = 0
local DST_PORT = 2

local function has_ipv4_src_port(port)
   return { '=', { '[ip*]', SRC_PORT, 2 }, port }
end
local function has_ipv4_dst_port(port)
   return { '=', { '[ip*]', DST_PORT, 2 }, port }
end
local function has_ipv4_port(port)
   return { 'or', has_ipv4_src_port(port), has_ipv4_dst_port(port) }
end
local function has_ipv6_src_port(port)
   return { '=', { '[ip6*]', SRC_PORT, 2 }, port }
end
local function has_ipv6_dst_port(port)
   return { '=', { '[ip6*]', DST_PORT, 2 }, port }
end
local function has_ipv6_port(port)
   return { 'or', has_ipv6_src_port(port), has_ipv6_dst_port(port) }
end
local function expand_dir_port(expr, has_ipv4_port, has_ipv6_port)
   local port = expr[2]
   return { 'if', { 'ip' },
            { 'and',
              { 'or', has_ipv4_protocol(PROTO_TCP),
                { 'or', has_ipv4_protocol(PROTO_UDP),
                  has_ipv4_protocol(PROTO_SCTP) } },
              has_ipv4_port(port) },
            { 'and',
              { 'or', has_ipv6_protocol(PROTO_TCP),
                { 'or', has_ipv6_protocol(PROTO_UDP),
                  has_ipv6_protocol(PROTO_SCTP) } },
              has_ipv6_port(port) } }
end
local function expand_port(expr)
   return expand_dir_port(expr, has_ipv4_port, has_ipv6_port)
end
local function expand_src_port(expr)
   return expand_dir_port(expr, has_ipv4_src_port, has_ipv6_src_port)
end
local function expand_dst_port(expr)
   return expand_dir_port(expr, has_ipv4_dst_port, has_ipv6_dst_port)
end

local function expand_proto_port(expr, proto)
   local port = expr[2]
   return { 'if', { 'ip' },
            { 'and',
              has_ipv4_protocol(proto),
              has_ipv4_port(port) },
            { 'and',
              has_ipv6_protocol(proto),
              has_ipv6_port(port) } }
end
local function expand_tcp_port(expr)
   return expand_proto_port(expr, PROTO_TCP)
end
local function expand_udp_port(expr)
   return expand_proto_port(expr, PROTO_UDP)
end

local function expand_proto_src_port(expr, proto)
   local port = expr[2]
   return { 'if', { 'ip' },
            { 'and',
              has_ipv4_protocol(proto),
              has_ipv4_src_port(port) },
            { 'and',
              has_ipv6_protocol(proto),
              has_ipv6_src_port(port) } }
end
local function expand_tcp_src_port(expr)
   return expand_proto_src_port(expr, PROTO_TCP)
end
local function expand_udp_src_port(expr)
   return expand_proto_src_port(expr, PROTO_UDP)
end

local function expand_proto_dst_port(expr, proto)
   local port = expr[2]
   return { 'if', { 'ip' },
            { 'and',
              has_ipv4_protocol(proto),
              has_ipv4_dst_port(port) },
            { 'and',
              has_ipv6_protocol(proto),
              has_ipv6_dst_port(port) } }
end
local function expand_tcp_dst_port(expr)
   return expand_proto_dst_port(expr, PROTO_TCP)
end
local function expand_udp_dst_port(expr)
   return expand_proto_dst_port(expr, PROTO_UDP)
end

-- Portrange operations
--
local function has_ipv4_src_portrange(lo, hi)
   return { 'and',
            { '<=', lo, { '[ip*]', SRC_PORT, 2 } },
            { '<=', { '[ip*]', SRC_PORT, 2 }, hi } }
end
local function has_ipv4_dst_portrange(lo, hi)
   return { 'and',
            { '<=', lo, { '[ip*]', DST_PORT, 2 } },
            { '<=', { '[ip*]', DST_PORT, 2 }, hi } }
end
local function has_ipv4_portrange(lo, hi)
   return { 'or', has_ipv4_src_portrange(lo, hi), has_ipv4_dst_portrange(lo, hi) }
end
local function has_ipv6_src_portrange(lo, hi)
   return { 'and',
            { '<=', lo, { '[ip6*]', SRC_PORT, 2 } },
            { '<=', { '[ip6*]', SRC_PORT, 2 }, hi } }
end
local function has_ipv6_dst_portrange(lo, hi)
   return { 'and',
            { '<=', lo, { '[ip6*]', DST_PORT, 2 } },
            { '<=', { '[ip6*]', DST_PORT, 2 }, hi } }
end
local function has_ipv6_portrange(lo, hi)
   return { 'or', has_ipv6_src_portrange(lo, hi), has_ipv6_dst_portrange(lo, hi) }
end
local function expand_dir_portrange(expr, has_ipv4_portrange, has_ipv6_portrange)
   local lo, hi = expr[2][1], expr[2][2]
   return { 'if', { 'ip' },
            { 'and',
              { 'or', has_ipv4_protocol(PROTO_TCP),
                { 'or', has_ipv4_protocol(PROTO_UDP),
                  has_ipv4_protocol(PROTO_SCTP) } },
              has_ipv4_portrange(lo, hi) },
            { 'and',
              { 'or', has_ipv6_protocol(PROTO_TCP),
                { 'or', has_ipv6_protocol(PROTO_UDP),
                  has_ipv6_protocol(PROTO_SCTP) } },
              has_ipv6_portrange(lo, hi) } }
end
local function expand_portrange(expr)
   return expand_dir_portrange(expr, has_ipv4_portrange, has_ipv6_portrange)
end
local function expand_src_portrange(expr)
   return expand_dir_portrange(expr, has_ipv4_src_portrange, has_ipv6_src_portrange)
end
local function expand_dst_portrange(expr)
   return expand_dir_portrange(expr, has_ipv4_dst_portrange, has_ipv6_dst_portrange)
end

local function expand_proto_portrange(expr, proto)
   local lo, hi = expr[2][1], expr[2][2]
   return { 'if', { 'ip' },
            { 'and',
              has_ipv4_protocol(proto),
              has_ipv4_portrange(lo, hi) },
            { 'and',
              has_ipv6_protocol(proto),
              has_ipv6_portrange(lo, hi) } }
end
local function expand_tcp_portrange(expr)
   return expand_proto_portrange(expr, PROTO_TCP)
end
local function expand_udp_portrange(expr)
   return expand_proto_portrange(expr, PROTO_UDP)
end

local function expand_proto_src_portrange(expr, proto)
   local lo, hi = expr[2][1], expr[2][2]
   return { 'if', { 'ip' },
            { 'and',
              has_ipv4_protocol(proto),
              has_ipv4_src_portrange(lo, hi) },
            { 'and',
              has_ipv6_protocol(proto),
              has_ipv6_src_portrange(lo, hi) } }
end
local function expand_tcp_src_portrange(expr)
   return expand_proto_src_portrange(expr, PROTO_TCP)
end
local function expand_udp_src_portrange(expr)
   return expand_proto_src_portrange(expr, PROTO_UDP)
end

local function expand_proto_dst_portrange(expr, proto)
   local lo, hi = expr[2][1], expr[2][2]
   return { 'if', { 'ip' },
            { 'and',
              has_ipv4_protocol(proto),
              has_ipv4_dst_portrange(lo, hi) },
            { 'and', 
              has_ipv6_protocol(proto),
              has_ipv6_dst_portrange(lo, hi) } }
end
local function expand_tcp_dst_portrange(expr)
   return expand_proto_dst_portrange(expr, PROTO_TCP)
end
local function expand_udp_dst_portrange(expr)
   return expand_proto_dst_portrange(expr, PROTO_UDP)
end

-- IP protocol

local proto_info = {
   ip   = { id = PROTO_IPV4,  access = "[ip]",    src = 12, dst = 16 },
   arp  = { id = PROTO_ARP,   access = "[arp]",   src = 14, dst = 24 },
   rarp = { id = PROTO_RARP,  access = "[rarp]",  src = 14, dst = 24 },
   ip6  = { id = PROTO_IPV6,  access = "[ip6]",   src =  8, dst = 24 },
}

local function has_proto_dir_host(proto, dir, addr, mask)
   local host = ipv4_to_int(addr)
   local val = { proto_info[proto].access, proto_info[proto][dir], 4 }
   if mask then
      mask = tonumber(mask) and 2^32 - 2^(32 - mask) or ipv4_to_int(mask)
      val = { '&', val, tonumber(mask) }
   end
   return { 'and', has_ether_protocol(proto_info[proto].id), { '=', val, host } }
end

local function expand_ip_src_host(expr)
  return has_proto_dir_host("ip", "src", expr[2], expr[3])
end
local function expand_ip_dst_host(expr)
   return has_proto_dir_host("ip", "dst", expr[2], expr[3])
end
local function expand_ip_host(expr)
   return { 'or', expand_ip_src_host(expr), expand_ip_dst_host(expr) }
end

local function expand_ip_broadcast(expr)
   error("netmask not known, so 'ip broadcast' not supported")
end
local function expand_ip6_broadcast(expr)
   error("only link-layer/IP broadcast filters supported")
end
local function expand_ip_multicast(expr)
   local IPV4_MULTICAST = 224 -- 0xe0
   local IPV4_DEST_ADDRESS = 16
   return { '=', { '[ip]', IPV4_DEST_ADDRESS, 1 }, IPV4_MULTICAST }
end
local function expand_ip6_multicast(expr)
   local IPV6_MULTICAST = 255 -- 0xff
   local IPV6_DEST_ADDRESS_OFFSET = 24 -- 14 + 24 = 38 (last two bytes of dest address)
   return { '=', { '[ip6]', IPV6_DEST_ADDRESS_OFFSET, 1 }, IPV6_MULTICAST }
end
local function expand_ip4_protochain(expr)
   -- FIXME: Not implemented yet. BPF code of ip protochain is rather complex.
   return unimplemented(expr)
end
local function expand_ip6_protochain(expr)
   -- FIXME: Not implemented yet. BPF code of ip6 protochain is rather complex.
   return unimplemented(expr)
end
local function expand_ip_protochain(expr)
   return { 'if', 'ip', expand_ip4_protochain(expr), expand_ip6_protochain(expr) }
end

local ip_protos = {
   icmp  = PROTO_ICMP,
   icmp6 = PROTO_ICMP6,
   igmp  = PROTO_IGMP,
   igrp  = PROTO_IGRP,
   pim   = PROTO_PIM,
   ah    = PROTO_AH,
   esp   = PROTO_ESP,
   vrrp  = PROTO_VRRP,
   udp   = PROTO_UDP,
   tcp   = PROTO_TCP,
   sctp  = PROTO_SCTP,
}

local function expand_ip4_proto(expr)
   local proto = expr[2]
   if type(proto) == 'string' then proto = ip_protos[proto] end
   return has_ipv4_protocol(assert(proto, "Invalid IP protocol"))
end

local function expand_ip6_proto(expr)
   local proto = expr[2]
   if type(proto) == 'string' then proto = ip_protos[proto] end
   return has_ipv6_protocol(assert(proto, "Invalid IP protocol"))
end

local function expand_ip_proto(expr)
   return { 'or', has_ipv4_protocol(expr[2]), has_ipv6_protocol(expr[2]) }
end

-- ISO

local iso_protos = {
   clnp = PROTO_CLNP,
   esis = PROTO_ESIS,
   isis = PROTO_ISIS,
}

local function has_iso_protocol(proto)
  return { 'and',
           { '<=', { '[ether]', ETHER_TYPE, 2 }, ETHER_MAX_LEN },
           { 'and',
             { '=', { '[ether]', ETHER_PAYLOAD, 2 }, PROTO_ISO },
             { '=', { '[ether]', ETHER_PAYLOAD + 3, 1 }, proto } } }
end

local function expand_iso_proto(expr)
   local proto = expr[2]
   if type(proto) == 'string' then proto = iso_protos[proto] end
   return has_iso_protocol(assert(proto, "Invalid ISO protocol"))
end

-- ARP protocol

local function expand_arp_src_host(expr)
   return has_proto_dir_host("arp", "src", expr[2], expr[3])
end
local function expand_arp_dst_host(expr)
   return has_proto_dir_host("arp", "dst", expr[2], expr[3])
end
local function expand_arp_host(expr)
   return { 'or', expand_arp_src_host(expr), expand_arp_dst_host(expr) }
end

-- RARP protocol

local function expand_rarp_src_host(expr)
   return has_proto_dir_host("rarp", "src", expr[2], expr[3])
end
local function expand_rarp_dst_host(expr)
   return has_proto_dir_host("rarp", "dst", expr[2], expr[3])
end
local function expand_rarp_host(expr)
   return { 'or', expand_rarp_src_host(expr), expand_rarp_dst_host(expr) }
end

-- IPv6

local function ipv6_dir_host(proto, dir, addr, mask_len)
   mask_len = mask_len or 128
   local offset = proto_info.ip6[dir]
   local ipv6 = ipv6_as_4x32(addr)

   local function match_ipv6_fragment(i)
      local fragment = ipv6[i]

      -- Calculate mask for fragment
      local mask = mask_len >= 32 and 0 or mask_len
      mask_len = mask_len >= 32 and mask_len - 32 or 0

      -- Retrieve address current offset
      local val = { proto_info.ip6.access, offset, 4 }
      offset = offset + 4

      if mask ~= 0 then val = { '&', val, 2^32 - 2^(32 - mask) } end
      return { '=', val, fragment }
   end

   -- Lowering of an IPv6 address does not require to go iterate through all
   -- IPv6 fragments (4x32). Once mask_len becomes 0 is possible to exit.
   local function match_ipv6(i)
      local i = i or 1
      local expr = match_ipv6_fragment(i)
      if mask_len == 0 or i > 4 then return expr end
      return { 'and', expr, match_ipv6(i + 1) }
   end

   return { 'and', has_ether_protocol(PROTO_IPV6), match_ipv6() }
end

local function expand_src_ipv6_host(expr)
   return ipv6_dir_host('ip6', 'src', expr[2], expr[3])
end
local function expand_dst_ipv6_host(expr)
   return ipv6_dir_host('ip6', 'dst', expr[2], expr[3])
end
local function expand_ipv6_host(expr)
   return { 'or',
            ipv6_dir_host('ip6', 'src', expr[2], expr[3]),
            ipv6_dir_host('ip6', 'dst', expr[2], expr[3]) }
end

-- Host


--[[
* Format IPv4 expr:
  { 'net', { 'ipv4', 127, 0, 0, 1 } }
  { 'ipv4/len', { 'ipv4', 127, 0, 0, 1 }, 24 }
* Format IPv6 expr:
  { 'net', { 'ipv6', 0, 0, 0, 0, 0, 0, 0, 1 } }
  { 'ipv4/len', { 'ipv6', 0, 0, 0, 0, 0, 0, 0, 1 }, 24 }
]]--
local function is_ipv6_addr(expr)
   return expr[2][1] == 'ipv6'
end

local function expand_src_host(expr)
   if is_ipv6_addr(expr) then return expand_src_ipv6_host(expr) end
   return { 'if', { 'ip' }, expand_ip_src_host(expr),
            { 'if', { 'arp' }, expand_arp_src_host(expr),
              expand_rarp_src_host(expr) } }
end
local function expand_dst_host(expr)
   if is_ipv6_addr(expr) then return expand_dst_ipv6_host(expr) end
   return { 'if', { 'ip' }, expand_ip_dst_host(expr),
            { 'if', { 'arp' }, expand_arp_dst_host(expr),
              expand_rarp_dst_host(expr) } }
end
-- Format IPv4: { 'ipv4/len', { 'ipv4', 127, 0, 0, 1 }, 8 }
-- Format IPv4: { 'ipv4/mask', { 'ipv4', 127, 0, 0, 1 }, { 'ipv4', 255, 0, 0, 0 } }
-- Format IPv6: { 'ipv6/len', { 'ipv6', 0, 0, 0, 0, 0, 0, 0, 1 }, 128 }
local function expand_host(expr)
   if is_ipv6_addr(expr) then return expand_ipv6_host(expr) end
   return { 'if', { 'ip' }, expand_ip_host(expr),
            { 'if', { 'arp' }, expand_arp_host(expr),
              expand_rarp_host(expr) } }
end

-- Ether

local MAC_DST = 0
local MAC_SRC = 6 

local function ehost_to_int(addr)
   assert(addr[1] == 'ehost', "Not a valid ehost address")
   return uint16(addr[2], addr[3]), uint32(addr[4], addr[5], addr[6], addr[7])
end
local function expand_ether_src_host(expr)
   local hi, lo = ehost_to_int(expr[2])
   return { 'and',
            { '=', { '[ether]', MAC_SRC, 2 }, hi },
            { '=', { '[ether]', MAC_SRC + 2, 4 }, lo } }
end
local function expand_ether_dst_host(expr)
   local hi, lo = ehost_to_int(expr[2])
   return { 'and',
            { '=', { '[ether]', MAC_DST, 2 }, hi },
            { '=', { '[ether]', MAC_DST + 2, 4 }, lo } }
end
local function expand_ether_host(expr)
   return { 'or', expand_ether_src_host(expr), expand_ether_dst_host(expr) }
end
local function expand_ether_broadcast(expr)
   local broadcast = { 'ehost', 255, 255, 255, 255, 255, 255 }
   local hi, lo = ehost_to_int(broadcast)
   return { 'and',
            { '=', { '[ether]', MAC_DST, 2 }, hi },
            { '=', { '[ether]', MAC_DST + 2, 4 }, lo } }
end
local function expand_ether_multicast(expr)
   return { '!=', { '&', { '[ether]', 0, 1 }, 1 }, 0 }
end

-- Ether protos

local function expand_ip(expr)
   return has_ether_protocol(PROTO_IPV4)
end
local function expand_ip6(expr)
   return has_ether_protocol(PROTO_IPV6)
end
local function expand_arp(expr)
   return has_ether_protocol(PROTO_ARP)
end
local function expand_rarp(expr)
   return has_ether_protocol(PROTO_RARP)
end

local function expand_atalk(expr)
  local ATALK_ID_1 = 491675     -- 0x7809B
  local ATALK_ID_2 = 2863268616 -- 0xaaaa0308
  return { 'or',
           has_ether_protocol(PROTO_ATALK),
           { 'if', { '>', { '[ether]', ETHER_TYPE, 2}, ETHER_MAX_LEN },
             { 'false' },
             { 'and',
               { '=', { '[ether]', ETHER_PAYLOAD + 4, 2 }, ATALK_ID_1 },
               { '=', { '[ether]', ETHER_PAYLOAD, 4 }, ATALK_ID_2 } } } }
end
local function expand_aarp(expr)
  local AARP_ID = 2863268608 -- 0xaaaa0300
  return { 'or',
           has_ether_protocol(PROTO_AARP),
           { 'if', { '>', { '[ether]', ETHER_TYPE, 2}, ETHER_MAX_LEN },
             { 'false' },
             { 'and',
               { '=', { '[ether]', ETHER_PAYLOAD + 4, 2 }, PROTO_AARP },
               { '=', { '[ether]', ETHER_PAYLOAD, 4 }, AARP_ID } } } }
end
local function expand_decnet(expr)
   return has_ether_protocol(PROTO_DECNET)
end
local function expand_sca(expr)
   return has_ether_protocol(PROTO_SCA)
end
local function expand_lat(expr)
   return has_ether_protocol(PROTO_LAT)
end
local function expand_mopdl(expr)
   return has_ether_protocol(PROTO_MOPDL)
end
local function expand_moprc(expr)
   return has_ether_protocol(PROTO_MOPRC)
end
local function expand_iso(expr)
   return { 'and',
            { '<=', { '[ether]', ETHER_TYPE, 2 }, ETHER_MAX_LEN },
            { '=', { '[ether]', ETHER_PAYLOAD, 2 }, PROTO_ISO } }
end
local function expand_stp(expr)
   return { 'and',
            { '<=', { '[ether]', ETHER_TYPE, 2 }, ETHER_MAX_LEN },
            { '=', { '[ether]', ETHER_PAYLOAD, 1 }, PROTO_STP } }
end

local function expand_ipx(expr)
  local IPX_SAP =      224        -- 0xe0
  local IPX_CHECKSUM = 65535      -- 0xffff
  local AARP_ID =      2863268608 -- 0xaaaa0300
  return { 'or',
           has_ether_protocol(PROTO_IPX),
           { 'if', { '>', { '[ether]', ETHER_TYPE, 2}, ETHER_MAX_LEN },
             { 'false' },
             { 'or',
               { 'and',
                 { '=', { '[ether]', ETHER_PAYLOAD + 4, 2 }, PROTO_IPX },
                 { '=', { '[ether]', ETHER_PAYLOAD, 4 }, AARP_ID } },
               { 'or',
                 { '=', { '[ether]', ETHER_PAYLOAD, 1 }, IPX_SAP },
                 { '=', { '[ether]', ETHER_PAYLOAD, 2 }, IPX_CHECKSUM } } } } }
end
local function expand_netbeui(expr)
   return { 'and',
            { '<=', { '[ether]', ETHER_TYPE, 2 }, ETHER_MAX_LEN },
            { '=', { '[ether]', ETHER_PAYLOAD, 2 }, PROTO_NETBEUI } }
end

local ether_protos = {
   ip      = expand_ip,
   ip6     = expand_ip6,
   arp     = expand_arp,
   rarp    = expand_rarp,
   atalk   = expand_atalk,
   aarp    = expand_aarp,
   decnet  = expand_decnet,
   sca     = expand_sca,
   lat     = expand_lat,
   mopdl   = expand_mopdl,
   moprc   = expand_moprc,
   iso     = expand_iso,
   stp     = expand_stp,
   ipx     = expand_ipx,
   netbeui = expand_netbeui,
}

local function expand_ether_proto(expr)
   local proto = expr[2]
   if type(proto) == 'string' then return ether_protos[proto](expr) end
   return has_ether_protocol(proto)
end

-- Net

local function expand_src_net(expr)
   local addr = expr
   local proto = expr[2][1]
   if proto:match("/len$") or proto:match("/mask$") then addr = expr[2] end
   if is_ipv6_addr(addr) then return expand_src_ipv6_host(addr) end
   return expand_src_host(addr)
end
local function expand_dst_net(expr)
   local addr = expr
   local proto = expr[2][1]
   if proto:match("/len$") or proto:match("/mask$") then addr = expr[2] end
   if is_ipv6_addr(addr) then return expand_dst_ipv6_host(addr) end
   return expand_dst_host(addr)
end

-- Format IPv4 expr: { 'net', { 'ipv4/len', { 'ipv4', 127, 0, 0, 0 }, 8 } }
-- Format IPV6 expr: { 'net', { 'ipv6/len', { 'ipv6', 0, 0, 0, 0, 0, 0, 0, 1 }, 128 } }
local function expand_net(expr)
   local addr = expr
   local proto = expr[2][1]
   if proto:match("/len$") or proto:match("/mask$") then addr = expr[2] end
   if is_ipv6_addr(addr) then return expand_ipv6_host(addr) end
   return expand_host(addr)
end

-- Packet length

local function expand_less(expr)
   return { '<=', 'len', expr[2] }
end
local function expand_greater(expr)
   return { '>=', 'len', expr[2] }
end

-- DECNET

local function expand_decnet_src(expr)
   local addr = expr[2]
   local addr_int = uint16(addr[2], addr[3])
   return { 'if', { '=', { '&', { '[ether]', ETHER_PAYLOAD + 2, 1}, 7 }, 2 },
            { '=', { '[ether]', ETHER_PAYLOAD + 5, 2}, addr_int },
            { 'if', { '=', { '&', { '[ether]', ETHER_PAYLOAD + 2, 2}, 65287 }, 33026 },
              { '=', { '[ether]', ETHER_PAYLOAD + 6, 2}, addr_int },
              { 'if', { '=', { '&', { '[ether]', ETHER_PAYLOAD + 2, 1}, 7 }, 6 },
                { '=', { '[ether]', ETHER_PAYLOAD + 17, 2}, addr_int },
                { 'if', { '=', { '&', { '[ether]', ETHER_PAYLOAD + 2, 2}, 65287 }, 33030 },
                  { '=', { '[ether]', ETHER_PAYLOAD + 18, 2}, addr_int },
                  { 'false' } } } } }
end
local function expand_decnet_dst(expr)
   local addr = expr[2]
   local addr_int = uint16(addr[2], addr[3])
   return { 'if', { '=', { '&', { '[ether]', ETHER_PAYLOAD + 2, 1}, 7 }, 2 },
            { '=', { '[ether]', ETHER_PAYLOAD + 3, 2}, addr_int },
            { 'if', { '=', { '&', { '[ether]', ETHER_PAYLOAD + 2, 2}, 65287 }, 33026 },
              { '=', { '[ether]', ETHER_PAYLOAD + 4, 2}, addr_int },
              { 'if', { '=', { '&', { '[ether]', ETHER_PAYLOAD + 2, 1}, 7 }, 6 },
                { '=', { '[ether]', ETHER_PAYLOAD + 9, 2}, addr_int },
                { 'if', { '=', { '&', { '[ether]', ETHER_PAYLOAD + 2, 2}, 65287 }, 33030 },
                  { '=', { '[ether]', ETHER_PAYLOAD + 10, 2}, addr_int },
                  { 'false' } } } } }
end
local function expand_decnet_host(expr)
   return { 'or', expand_decnet_src(expr), expand_decnet_dst(expr) }
end

-- IS-IS

local L1_IIH   = 15  -- 0x0F
local L2_IIH   = 16  -- 0x10
local PTP_IIH  = 17  -- 0x11
local L1_LSP   = 18  -- 0x12
local L2_LSP   = 20  -- 0x14
local L1_CSNP  = 24  -- 0x18
local L2_CSNP  = 25  -- 0x19
local L1_PSNP  = 26  -- 0x1A
local L2_PSNP  = 27  -- 0x1B

local function expand_isis_protocol(...)
   local function concat(lop, reg, values, i)
      i = i or 1
      if i == #values then return { '=', reg, values[i] } end
      return { lop, { '=', reg, values[i] }, concat(lop, reg, values, i+1) }
   end
   return { 'if', has_iso_protocol(PROTO_ISIS),
            concat('or', { '[ether]', ETHER_PAYLOAD + 7, 1 }, {...} ),
            { 'false' } }
end
local function expand_l1(expr)
   return expand_isis_protocol(L1_IIH, L1_LSP, L1_CSNP, L1_PSNP, PTP_IIH)
end
local function expand_l2(expr)
   return expand_isis_protocol(L2_IIH, L2_LSP, L2_CSNP, L2_PSNP, PTP_IIH)
end
local function expand_iih(expr)
   return expand_isis_protocol(L1_IIH, L2_IIH, PTP_IIH)
end
local function expand_lsp(expr)
   return expand_isis_protocol(L1_LSP, L2_LSP)
end
local function expand_snp(expr)
   return expand_isis_protocol(L1_CSNP, L2_CSNP, L1_PSNP, L2_PSNP)
end
local function expand_csnp(expr)
   return expand_isis_protocol(L1_CSNP, L2_CSNP)
end
local function expand_psnp(expr)
   return expand_isis_protocol(L1_PSNP, L2_PSNP)
end

local primitive_expanders = {
   dst_host = expand_dst_host,
   dst_net = expand_dst_net,
   dst_port = expand_dst_port,
   dst_portrange = expand_dst_portrange,
   src_host = expand_src_host,
   src_net = expand_src_net,
   src_port = expand_src_port,
   src_portrange = expand_src_portrange,
   host = expand_host,
   ether_src = expand_ether_src_host,
   ether_src_host = expand_ether_src_host,
   ether_dst = expand_ether_dst_host,
   ether_dst_host = expand_ether_dst_host,
   ether_host = expand_ether_host,
   ether_broadcast = expand_ether_broadcast,
   fddi_src = expand_ether_src_host,
   fddi_src_host = expand_ether_src_host,
   fddi_dst = expand_ether_dst_host,
   fddi_dst_host = expand_ether_dst_host,
   fddi_host = expand_ether_host,
   fddi_broadcast = expand_ether_broadcast,
   tr_src = expand_ether_src_host,
   tr_src_host = expand_ether_src_host,
   tr_dst = expand_ether_dst_host,
   tr_dst_host = expand_ether_dst_host,
   tr_host = expand_ether_host,
   tr_broadcast = expand_ether_broadcast,
   wlan_src = expand_ether_src_host,
   wlan_src_host = expand_ether_src_host,
   wlan_dst = expand_ether_dst_host,
   wlan_dst_host = expand_ether_dst_host,
   wlan_host = expand_ether_host,
   wlan_broadcast = expand_ether_broadcast,
   broadcast = expand_ether_broadcast,
   ether_multicast = expand_ether_multicast,
   multicast = expand_ether_multicast,
   ether_proto = expand_ether_proto,
   gateway = unimplemented,
   net = expand_net,
   port = expand_port,
   portrange = expand_portrange,
   less = expand_less,
   greater = expand_greater,
   ip = expand_ip,
   ip_proto = expand_ip4_proto,
   ip_protochain = expand_ip4_protochain,
   ip_host = expand_ip_host,
   ip_src = expand_ip_src_host,
   ip_src_host = expand_ip_src_host,
   ip_dst = expand_ip_dst_host,
   ip_dst_host = expand_ip_dst_host,
   ip_broadcast = expand_ip_broadcast,
   ip_multicast = expand_ip_multicast,
   ip6 = expand_ip6,
   ip6_proto = expand_ip6_proto,
   ip6_protochain = expand_ip6_protochain,
   ip6_broadcast = expand_ip6_broadcast,
   ip6_multicast = expand_ip6_multicast,
   proto = expand_ip_proto,
   tcp = function(expr) return has_ip_protocol(PROTO_TCP) end,
   tcp_port = expand_tcp_port,
   tcp_src_port = expand_tcp_src_port,
   tcp_dst_port = expand_tcp_dst_port,
   tcp_portrange = expand_tcp_portrange,
   tcp_src_portrange = expand_tcp_src_portrange,
   tcp_dst_portrange = expand_tcp_dst_portrange,
   udp = function(expr) return has_ip_protocol(PROTO_UDP) end,
   udp_port = expand_udp_port,
   udp_src_port = expand_udp_src_port,
   udp_dst_port = expand_udp_dst_port,
   udp_portrange = expand_udp_portrange,
   udp_src_portrange = expand_udp_src_portrange,
   udp_dst_portrange = expand_udp_dst_portrange,
   icmp = function(expr) return has_ip_protocol(PROTO_ICMP) end,
   icmp6 = function(expr) return has_ipv6_protocol(PROTO_ICMP6) end,
   igmp = function(expr) return has_ip_protocol(PROTO_IGMP) end,
   igrp = function(expr) return has_ip_protocol(PROTO_IGRP) end,
   pim = function(expr) return has_ip_protocol(PROTO_PIM) end,
   ah = function(expr) return has_ip_protocol(PROTO_AH) end,
   esp = function(expr) return has_ip_protocol(PROTO_ESP) end,
   vrrp = function(expr) return has_ip_protocol(PROTO_VRRP) end,
   sctp = function(expr) return has_ip_protocol(PROTO_SCTP) end,
   protochain = expand_ip_protochain,
   arp = expand_arp,
   arp_host = expand_arp_host,
   arp_src = expand_arp_src_host,
   arp_src_host = expand_arp_src_host,
   arp_dst = expand_arp_dst_host,
   arp_dst_host = expand_arp_dst_host,
   rarp = expand_rarp,
   rarp_host = expand_rarp_host,
   rarp_src = expand_rarp_src_host,
   rarp_src_host = expand_rarp_src_host,
   rarp_dst = expand_rarp_dst_host,
   rarp_dst_host = expand_rarp_dst_host,
   atalk = expand_atalk,
   aarp = expand_aarp,
   decnet = expand_decnet,
   decnet_src = expand_decnet_src,
   decnet_src_host = expand_decnet_src,
   decnet_dst = expand_decnet_dst,
   decnet_dst_host = expand_decnet_dst,
   decnet_host = expand_decnet_host,
   iso = expand_iso,
   stp = expand_stp,
   ipx = expand_ipx,
   netbeui = expand_netbeui,
   sca = expand_sca,
   lat = expand_lat,
   moprc = expand_moprc,
   mopdl = expand_mopdl,
   llc = unimplemented,
   ifname = unimplemented,
   on = unimplemented,
   rnr = unimplemented,
   rulenum = unimplemented,
   reason = unimplemented,
   rset = unimplemented,
   ruleset = unimplemented,
   srnr = unimplemented,
   subrulenum = unimplemented,
   action = unimplemented,
   wlan_ra = unimplemented,
   wlan_ta = unimplemented,
   wlan_addr1 = unimplemented,
   wlan_addr2 = unimplemented,
   wlan_addr3 = unimplemented,
   wlan_addr4 = unimplemented,
   type = unimplemented,
   type_subtype = unimplemented,
   subtype = unimplemented,
   dir = unimplemented,
   vlan = unimplemented,
   mpls = unimplemented,
   pppoed = unimplemented,
   pppoes = unimplemented,
   iso_proto = expand_iso_proto,
   clnp = function(expr) return has_iso_protocol(PROTO_CLNP) end,
   esis = function(expr) return has_iso_protocol(PROTO_ESIS) end,
   isis = function(expr) return has_iso_protocol(PROTO_ISIS) end,
   l1 = expand_l1,
   l2 = expand_l2,
   iih = expand_iih,
   lsp = expand_lsp,
   snp = expand_snp,
   csnp = expand_csnp,
   psnp = expand_psnp,
   vpi = unimplemented,
   vci = unimplemented,
   lane = unimplemented,
   oamf4s = unimplemented,
   oamf4e = unimplemented,
   oamf4 = unimplemented,
   oam = unimplemented,
   metac = unimplemented,
   bcc = unimplemented,
   sc = unimplemented,
   ilmic = unimplemented,
   connectmsg = unimplemented,
   metaconnect = unimplemented
}

local relops = set('<', '<=', '=', '!=', '>=', '>')

local addressables = set(
   'arp', 'rarp', 'wlan', 'ether', 'fddi', 'tr', 'ppp',
   'slip', 'link', 'radio', 'ip', 'ip6', 'tcp', 'udp', 'icmp'
)

local binops = set(
   '+', '-', '*', '*64', '/', '&', '|', '^', '&&', '||', '<<', '>>'
)
local associative_binops = set(
   '+', '*', '*64', '&', '|', '^'
)
local bitops = set('&', '|', '^')
local unops = set('ntohs', 'ntohl', 'uint32')
local leaf_primitives = set(
   'true', 'false', 'fail'
)

local function expand_offset(level, dlt)
   assert(dlt == "EN10MB", "Encapsulation other than EN10MB unimplemented")
   local function guard_expr(expr)
      local test, guards = expand_relop(expr, dlt)
      return concat(guards, { { test, { 'false' } } })
   end
   local function guard_ether_protocol(proto)
      return concat(guard_expr(has_ether_protocol(proto)),
                    guard_expr(has_ether_protocol_min_payload(proto)))
   end
   function guard_ipv4_protocol(proto)
      return concat(guard_expr(has_ipv4_protocol(proto)),
                    guard_expr(has_ipv4_protocol_min_payload(proto)))
   end
   function guard_ipv6_protocol(proto)
      return concat(guard_expr(has_ipv6_protocol(proto)),
                    guard_expr(has_ipv6_protocol_min_payload(proto)))
   end
   function guard_first_ipv4_fragment()
      return guard_expr(is_first_ipv4_fragment())
   end
   function ipv4_payload_offset(proto)
      local ip_offset, guards = expand_offset('ip', dlt)
      if proto then
         guards = concat(guards, guard_ipv4_protocol(proto))
      end
      guards = concat(guards, guard_first_ipv4_fragment())
      local res = { '+',
                    { '<<', { '&', { '[]', ip_offset, 1 }, 0xf }, 2 },
                    ip_offset }
      return res, guards
   end
   function ipv6_payload_offset(proto)
      local ip_offset, guards = expand_offset('ip6', dlt)
      if proto then
         guards = concat(guards, guard_ipv6_protocol(proto))
      end
      return { '+', ip_offset, 40 }, guards
   end

   -- Note that unlike their corresponding predicates which detect
   -- either IPv4 or IPv6 traffic, [icmp], [udp], and [tcp] only work
   -- for IPv4.
   if level == 'ether' then
      return 0, {}
   elseif level == 'ether*' then
      return ETHER_PAYLOAD, {}
   elseif level == 'arp' then
      return ETHER_PAYLOAD, guard_ether_protocol(PROTO_ARP)
   elseif level == 'rarp' then
      return ETHER_PAYLOAD, guard_ether_protocol(PROTO_RARP)
   elseif level == 'ip' then
      return ETHER_PAYLOAD, guard_ether_protocol(PROTO_IPV4)
   elseif level == 'ip6' then
      return ETHER_PAYLOAD, guard_ether_protocol(PROTO_IPV6)
   elseif level == 'ip*' then
      return ipv4_payload_offset()
   elseif level == 'ip6*' then
      return ipv6_payload_offset()
   elseif level == 'icmp' then
      return ipv4_payload_offset(PROTO_ICMP)
   elseif level == 'udp' then
      return ipv4_payload_offset(PROTO_UDP)
   elseif level == 'tcp' then
      return ipv4_payload_offset(PROTO_TCP)
   elseif level == 'igmp' then
      return ipv4_payload_offset(PROTO_IGMP)
   elseif level == 'igrp' then
      return ipv4_payload_offset(PROTO_IGRP)
   elseif level == 'pim' then
      return ipv4_payload_offset(PROTO_PIM)
   elseif level == 'sctp' then
      return ipv4_payload_offset(PROTO_SCTP)
   elseif level == 'vrrp' then
      return ipv4_payload_offset(PROTO_VRRP)
   end
   error('invalid level '..level)
end

-- Returns two values: the expanded arithmetic expression and an ordered
-- list of guards.  A guard is a two-element array whose first element
-- is a test expression.  If all test expressions of the guards are
-- true, then it is valid to evaluate the arithmetic expression.  The
-- second element of the guard array is the expression to which the
-- relop will evaluate if the guard expression fails: either { 'false' }
-- or { 'fail' }.
function expand_arith(expr, dlt)
   assert(expr)
   if type(expr) == 'number' or expr == 'len' then return expr, {} end

   local op = expr[1]
   if binops[op] then
      -- Use 64-bit multiplication by default.  The optimizer will
      -- reduce this back to Lua's normal float multiplication if it
      -- can.
      if op == '*' then op = '*64' end
      local lhs, lhs_guards = expand_arith(expr[2], dlt)
      local rhs, rhs_guards = expand_arith(expr[3], dlt)
      -- Mod 2^32 to preserve uint32 range.
      local ret = { 'uint32', { op, lhs, rhs } }
      local guards = concat(lhs_guards, rhs_guards)
      -- RHS of division can't be 0.
      if op == '/' then
         local div_guard = { { '!=', rhs, 0 }, { 'fail' } }
         guards = concat(guards, { div_guard })
      end
      return ret, guards
   end

   local is_addr = false
   if op == 'addr' then
      is_addr = true
      expr = expr[2]
      op = expr[1]
   end
   assert(op ~= '[]', "expr has already been expanded?")
   local addressable = assert(op:match("^%[(.+)%]$"), "bad addressable")
   local offset, offset_guards = expand_offset(addressable, dlt)
   local lhs, lhs_guards = expand_arith(expr[2], dlt)
   local size = expr[3]
   local len_test = { '<=', { '+', { '+', offset, lhs }, size }, 'len' }
   -- ip[100000] will abort the whole matcher.  &ip[100000] will just
   -- cause the clause to fail to match.
   local len_guard = { len_test, is_addr and { 'false' } or { 'fail' } }
   local guards = concat(concat(offset_guards, lhs_guards), { len_guard })
   local addr =  { '+', offset, lhs }
   if is_addr then return addr, guards end
   local ret = { '[]', addr, size }
   if size == 1 then return ret, guards end
   if size == 2 then return { 'ntohs', ret }, guards end
   if size == 4 then return { 'uint32', { 'ntohl', ret } }, guards end
   error('unreachable')
end

function expand_relop(expr, dlt)
   local lhs, lhs_guards = expand_arith(expr[2], dlt)
   local rhs, rhs_guards = expand_arith(expr[3], dlt)
   return { expr[1], lhs, rhs }, concat(lhs_guards, rhs_guards)
end

function expand_bool(expr, dlt)
   assert(type(expr) == 'table', 'logical expression must be a table')
   if expr[1] == 'not' or expr[1] == '!' then
      return { 'if', expand_bool(expr[2], dlt), { 'false' }, { 'true' } }
   elseif expr[1] == 'and' or expr[1] == '&&' then
      return { 'if', expand_bool(expr[2], dlt),
               expand_bool(expr[3], dlt),
               { 'false' } }
   elseif expr[1] == 'or' or expr[1] == '||' then
      return { 'if', expand_bool(expr[2], dlt),
               { 'true' },
               expand_bool(expr[3], dlt) }
   elseif relops[expr[1]] then
      -- An arithmetic relop.
      local res, guards = expand_relop(expr, dlt)
      -- We remove guards in LIFO order, resulting in an expression
      -- whose first guard expression is the first one that was added.
      while #guards ~= 0 do
         local guard = table.remove(guards)
         assert(guard[2])
         res = { 'if', guard[1], res, guard[2] }
      end
      return res
   elseif expr[1] == 'if' then
      return { 'if',
               expand_bool(expr[2], dlt),
               expand_bool(expr[3], dlt),
               expand_bool(expr[4], dlt) }
   elseif leaf_primitives[expr[1]] then
      return expr
   else
      -- A logical primitive.
      local expander = primitive_expanders[expr[1]]
      assert(expander, "unimplemented primitive: "..expr[1])
      local expanded = expander(expr, dlt)
      return expand_bool(expander(expr, dlt), dlt)
   end
end

function expand(expr, dlt)
   dlt = dlt or 'RAW'
   expr = expand_bool(expr, dlt)
   if verbose then pp(expr) end
   return expr
end

function selftest ()
   print("selftest: pf.expand")
   local parse = require('pf.parse').parse
   local equals, assert_equals = utils.equals, utils.assert_equals
   assert_equals({ '=', 1, 2 },
      expand(parse("1 = 2"), 'EN10MB'))
   assert_equals({ '=', 1, "len" },
      expand(parse("1 = len"), 'EN10MB'))
   assert_equals({ 'if',
                   { '!=', 2, 0},
                   { '=', 1, { 'uint32', { '/', 2, 2} } },
                   { 'fail'} },
      expand(parse("1 = 2/2"), 'EN10MB'))
   assert_equals({ 'if',
                   { '<=', { '+', { '+', 0, 0 }, 1 }, 'len'},
                   { '=', { '[]', { '+', 0, 0 }, 1 }, 2 },
                   { 'fail' } },
      expand(parse("ether[0] = 2"), 'EN10MB'))
   -- Could check this, but it's very large
   expand(parse("tcp port 80 and (((ip[2:2] - ((ip[0]&0xf)<<2)) - ((tcp[12]&0xf0)>>2)) != 0)"),
          "EN10MB")
   print("OK")
end
