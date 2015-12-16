module(..., package.seeall)

local bt = require("apps.lwaftr.binding_table")
local constants = require("apps.lwaftr.constants")
local fragmentv4 = require("apps.lwaftr.fragmentv4")
local fragmentv6 = require("apps.lwaftr.fragmentv6")
local icmp = require("apps.lwaftr.icmp")
local lwconf = require("apps.lwaftr.conf")
local lwdebug = require("apps.lwaftr.lwdebug")
local lwheader = require("apps.lwaftr.lwheader")
local lwutil = require("apps.lwaftr.lwutil")

local S = require("syscall")
local timer = require("core.timer")
local checksum = require("lib.checksum")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local ipv4 = require("lib.protocol.ipv4")
local packet = require("core.packet")
local lib = require("core.lib")
local bit = require("bit")
local ffi = require("ffi")

local band, bor, bnot, rshift, lshift = bit.band, bit.bor, bit.bnot, bit.rshift, bit.lshift
local C = ffi.C
local cast, fstring = ffi.cast, ffi.string
local receive, transmit = link.receive, link.transmit
local rd16, rd32, get_ihl_from_offset = lwutil.rd16, lwutil.rd32, lwutil.get_ihl_from_offset
local set, keys, write_to_file = lwutil.set, lwutil.keys, lwutil.write_to_file
local ipv4number_to_str = lwutil.ipv4number_to_str
local write_eth_header, write_ipv6_header = lwheader.write_eth_header, lwheader.write_ipv6_header 

local debug = false

local CONF_FILE_DUMP = "/tmp/lwaftr-%s.conf"
local BINDING_TABLE_FILE_DUMP = "/tmp/binding-%s.table"

local function compute_binding_table_by_ipv4(binding_table)
   local ret = {}
   for _,bind in ipairs(binding_table) do
      ret[bind[2]] = bind
   end
   return ret
end

local function guarded_transmit(pkt, o)
   -- The assert was never being hit, and the assert+link check slow the code
   -- down about 5-18%, by comparing best and worst runs of 5 seconds at their
   -- starts and ends.
   -- The downside is that if the link actually is full, the packet will be dropped.
   -- Given the requirements of this project, rare dropped packets (none so far in
   -- testing) are better than a non-trivial speed decrease).
   -- The assert should never appear in production, but code to cache packets
   -- on a link full condition could.
   --assert(not full(o), "need a cache...")
   transmit(o, pkt)
end

local transmit_icmpv6_with_rate_limit

local function init_transmit_icmpv6_with_rate_limit(lwstate)
   assert(lwstate.icmpv6_rate_limiter_n_seconds > 0,
      "Incorrect icmpv6_rate_limiter_n_seconds value, must be > 0")
   assert(lwstate.icmpv6_rate_limiter_n_packets >= 0,
      "Incorrect icmpv6_rate_limiter_n_packets value, must be >= 0")
   local icmpv6_rate_limiter_n_seconds = lwstate.icmpv6_rate_limiter_n_seconds
   local icmpv6_rate_limiter_n_packets = lwstate.icmpv6_rate_limiter_n_packets
   local counter = 0
   local last_time
   return function (pkt, o)
      local cur_now = tonumber(engine.now())
      last_time = last_time or cur_now
      -- Reset if elapsed time reached.
      if cur_now - last_time >= icmpv6_rate_limiter_n_seconds then
         last_time = cur_now
         counter = 0
      end
      -- Send packet if limit not reached.
      if counter < icmpv6_rate_limiter_n_packets then
         guarded_transmit(pkt, o)
         counter = counter + 1
      else
         packet.free(pkt)
      end
   end
end

local function on_signal(sig, f)
   local fd = S.signalfd(sig, "nonblock") -- handle signal via fd
   local buf = S.types.t.siginfos(8)
   S.sigprocmask("block", sig)            -- block traditional handler
   timer.activate(timer.new(sig, function ()
      local events, err = S.util.signalfd_read(fd, buf)
      if events and #events > 0 then
         print(("[snabb-lwaftr: %s caught]"):format(sig:upper()))
         f()
      end
  end, 1e4, 'repeating'))
end

local function reload_binding_table(lwstate)
   if not lwstate.bt_file then return end
   print("Reload binding table")
   lwstate.binding_table = bt.load_binding_table(lwstate.bt_file)
   lwstate.binding_table_by_ipv4 = compute_binding_table_by_ipv4(lwstate.binding_table)
end

local function dump_configuration(lwstate)
   print("Dump configuration")
   local result = {}
   local etharr = set('aftr_mac_b4_side',  'aftr_mac_inet_side', 'b4_mac',  'inet_mac')
   local ipv4arr = set('aftr_ipv4_ip')
   local ipv6arr = set('aftr_ipv6_ip')
   local val
   for _, k in ipairs(lwstate.conf_keys) do
      local v = lwstate[k]
      if etharr[k] then
         val = ("ethernet:pton('%s')"):format(ethernet:ntop(v))
      elseif ipv4arr[k] then
         val = ("ipv4:pton('%s')"):format(ipv4:ntop(v))
      elseif ipv6arr[k] then
         val = ("ipv6:pton('%s')"):format(ipv6:ntop(v))
      elseif type(v) == "bool" then
         val = v and "true" or "false"
      elseif k == "binding_table" then
         val = "bt.get_binding_table()"
      else
         val = lwstate[k]
      end
      table.insert(result, ("%s = %s"):format(k, val))
   end
   local filename = (CONF_FILE_DUMP):format(os.date("%Y-%m-%d-%H:%M:%S"))
   local content = table.concat(result, ",\n")
   write_to_file(filename, content)
   print(("Configuration written to %s"):format(filename))
end

local function dump_binding_table(lwstate)
   print("Dump binding table")
   local content = {}
   local function write(str)
      table.insert(content, str)
   end
   local function dump()
      return table.concat(content, "\n")
   end
   local function format_entry(entry)
      local v6, v4, port_start, port_end, br_v6 = entry[1], entry[2], entry[3], entry[4], entry[5]
      local result = {}
      table.insert(result, ("'%s'"):format(ipv6:ntop(v6)))
      table.insert(result, ("'%s'"):format(ipv4number_to_str(v4)))
      table.insert(result, port_start)
      table.insert(result, port_end)
      if br_v6 then
         table.insert(result, ("'%s'"):format(ipv6:ntop(br_v6)))
      end
      return table.concat(result, ",")
   end
   -- Write entries to content
   write("{")
   for _, entry in ipairs(lwstate.binding_table) do
      write(("\t{%s},"):format(format_entry(entry)))
   end
   write("}")
   -- Dump content to file
   local filename = (BINDING_TABLE_FILE_DUMP):format(os.date("%Y-%m-%d-%H:%M:%S"))
   write_to_file(filename, dump())
   print(("Binding table written to %s"):format(filename))
end

LwAftr = {}

function LwAftr:new(conf)
   if conf.debug then debug = true end
   local o = {}
   for k,v in pairs(conf) do
      o[k] = v
   end
   if conf.vlan_tagging then
      assert(o.v4_vlan_tag > 0 and o.v4_vlan_tag < 4096,
         "VLAN tag should be a value between 0 and 4095")
      assert(o.v6_vlan_tag > 0 and o.v6_vlan_tag < 4096,
         "VLAN tag should be a value between 0 and 4095")
      o.l2_size = constants.ethernet_header_size + 4
      o.o_ethernet_tag = constants.o_ethernet_ethertype
      o.o_ethernet_ethertype = constants.o_ethernet_ethertype + 4
      o.v4_vlan_tag = C.htonl(bor(lshift(constants.dotq_tpid, 16), o.v4_vlan_tag))
      o.v6_vlan_tag = C.htonl(bor(lshift(constants.dotq_tpid, 16), o.v6_vlan_tag))
   else
      o.l2_size = constants.ethernet_header_size
      o.o_ethernet_ethertype = constants.o_ethernet_ethertype
   end
   o.binding_table_by_ipv4 = compute_binding_table_by_ipv4(o.binding_table)
   o.fragment6_cache = {}
   o.fragment4_cache = {}
   transmit_icmpv6_with_rate_limit = init_transmit_icmpv6_with_rate_limit(o)
   on_signal("hup", function() reload_binding_table(o) end)
   on_signal("usr1", function()
      dump_configuration(o)
      dump_binding_table(o)
   end)
   o.conf_keys = keys(conf)
   if debug then lwdebug.pp(conf) end
   return setmetatable(o, {__index=LwAftr})
end

local function fixup_checksum(pkt, csum_offset, fixup_val)
   assert(math.abs(fixup_val) <= 0xffff, "Invalid fixup")
   local csum = bnot(C.ntohs(rd16(pkt.data + csum_offset)))
   if debug then print("old csum", string.format("%x", csum)) end
   csum = csum + fixup_val
   -- TODO/FIXME: *test* this code
   -- Manually unrolled loop; max 2 iterations, extra iterations
   -- don't hurt, bitops are fast and ifs are slow.
   local overflow = rshift(csum, 16)
   csum = band(csum, 0xffff) + overflow
   local overflow = rshift(csum, 16)
   csum = band(csum, 0xffff) + overflow
   csum = bnot(csum)

   if debug then print("new csum", string.format("%x", csum)) end
   pkt.data[csum_offset] = rshift(csum, 8)
   pkt.data[csum_offset + 1] = band(csum, 0xff)
end

local function decrement_ttl(lwstate, pkt)
   local ttl_offset = lwstate.l2_size + constants.o_ipv4_ttl
   pkt.data[ttl_offset] = pkt.data[ttl_offset] - 1
   local ttl = pkt.data[ttl_offset]
   local csum_offset = lwstate.l2_size + constants.o_ipv4_checksum
   -- ttl_offset is even, so multiply the ttl change by 0x100.
   fixup_checksum(pkt, csum_offset, -0x100)
   return ttl
end

local function get_lwAFTR_ipv6(lwstate, binding_entry)
   local lwaftr_ipv6 = binding_entry[5]
   if not lwaftr_ipv6 then lwaftr_ipv6 = lwstate.aftr_ipv6_ip end
   return lwaftr_ipv6
end

-- TODO: make this O(1), and seriously optimize it for cache lines
local function binding_lookup_ipv4(lwstate, ipv4_ip, port)
   if debug then
      print(lwdebug.format_ipv4(ipv4_ip), 'port: ', port, string.format("%x", port))
      lwdebug.pp(lwstate.binding_table)
   end
   for i=1,#lwstate.binding_table do
      local bind = lwstate.binding_table[i]
      if debug then print("CHECK", string.format("%x, %x", bind[2], ipv4_ip)) end
      if bind[2] == ipv4_ip then
         if port >= bind[3] and port <= bind[4] then
            local lwaftr_ipv6 = get_lwAFTR_ipv6(lwstate, bind)
            return bind[1], lwaftr_ipv6
         end
      end
   end
   if debug then
      print("Nothing found for ipv4:port", lwdebug.format_ipv4(ipv4_ip),
      string.format("%i (0x%x)", port, port))
   end
end

-- https://www.ietf.org/id/draft-farrer-softwire-br-multiendpoints-01.txt
-- Return the destination IPv6 address, *and the source IPv6 address*
local function binding_lookup_dst_ipv4_from_pkt(lwstate, pkt, pre_ipv4_bytes)
   local dst_ip_start = pre_ipv4_bytes + constants.o_ipv4_dst_addr
   -- Note: ip is kept in network byte order, regardless of host byte order
   local ip = rd32(pkt.data + dst_ip_start)
   local dst_port_start = pre_ipv4_bytes + get_ihl_from_offset(pkt, pre_ipv4_bytes) + 2
   local port = C.ntohs(rd16(pkt.data + dst_port_start))
   return binding_lookup_ipv4(lwstate, ip, port)
end

local function binding_lookup_src_ipv4_from_pkt(lwstate, pkt, pre_ipv4_bytes)
   local src_ip_start = pre_ipv4_bytes + constants.o_ipv4_src_addr
   -- Note: ip is kept in network byte order, regardless of host byte order
   local ip = rd32(pkt.data + src_ip_start)
   local src_port_start = pre_ipv4_bytes + get_ihl_from_offset(pkt, pre_ipv4_bytes)
   local port = C.ntohs(rd16(pkt.data + src_port_start))
   return binding_lookup_ipv4(lwstate, ip, port)
end

-- https://www.ietf.org/id/draft-farrer-softwire-br-multiendpoints-01.txt
-- Return true if the destination ipv4 address is within our managed set of addresses
local function ipv4_dst_in_binding_table(lwstate, pkt, pre_ipv4_bytes)
   local dst_ip_start = pre_ipv4_bytes + 16
   -- Note: ip is kept in network byte order, regardless of host byte order
   local ip = rd32(pkt.data + dst_ip_start)
   return lwstate.binding_table_by_ipv4[ip]
end

-- Todo: make this O(1)
local function in_binding_table(lwstate, ipv6_src_ip, ipv6_dst_ip, ipv4_src_ip, ipv4_src_port)
   local binding_table = lwstate.binding_table
   for i=1,#binding_table do
      local bind = binding_table[i]
      if debug then
         print("CHECKB4", string.format("%s, src=%s:%i",
               lwdebug.format_ipv4(C.ntohl(bind[2])),
               lwdebug.format_ipv4(C.ntohl(ipv4_src_ip)), ipv4_src_port))
      end
      if bind[2] == ipv4_src_ip then
         if ipv4_src_port >= bind[3] and ipv4_src_port <= bind[4] then
            if debug then
               print("ipv6bind")
               lwdebug.print_ipv6(bind[1])
               lwdebug.print_ipv6(ipv6_src_ip)
            end
            if C.memcmp(bind[1], ipv6_src_ip, 16) == 0 then
               local expected_dst = get_lwAFTR_ipv6(lwstate, bind)
               if debug then
                  print("DST_MEMCMP", expected_dst, ipv6_dst_ip)
                  lwdebug.print_ipv6(expected_dst)
                  lwdebug.print_ipv6(ipv6_dst_ip)
               end
               if C.memcmp(expected_dst, ipv6_dst_ip, 16) == 0 then
                  return true
               end
            end
         end
      end
   end
   return false
end

-- ICMPv4 type 3 code 1, as per RFC 7596.
-- The target IPv4 address + port is not in the table.
local function icmp_after_discard(lwstate, pkt, to_ip)
   local icmp_config = {type = constants.icmpv4_dst_unreachable,
                        code = constants.icmpv4_host_unreachable,
                        vlan_tag = lwstate.v4_vlan_tag
                        }
   local icmp_dis = icmp.new_icmpv4_packet(lwstate.aftr_mac_inet_side, lwstate.inet_mac,
                                           lwstate.aftr_ipv4_ip, to_ip, pkt,
                                           lwstate.l2_size, icmp_config)
   guarded_transmit(icmp_dis, lwstate.o4)
end

-- ICMPv6 type 1 code 5, as per RFC 7596.
-- The source (ipv6, ipv4, port) tuple is not in the table.
local function icmp_b4_lookup_failed(lwstate, pkt, to_ip)
   local icmp_config = {type = constants.icmpv6_dst_unreachable,
                        code = constants.icmpv6_failed_ingress_egress_policy,
                        vlan_tag = lwstate.v6_vlan_tag
                       }
   local b4fail_icmp = icmp.new_icmpv6_packet(lwstate.aftr_mac_b4_side, lwstate.b4_mac,
                                              lwstate.aftr_ipv6_ip, to_ip, pkt,
                                              lwstate.l2_size, icmp_config)
   transmit_icmpv6_with_rate_limit(b4fail_icmp, lwstate.o6)
end

-- Given a packet containing IPv4 and Ethernet, encapsulate the IPv4 portion.
local function ipv6_encapsulate(lwstate, pkt, next_hdr_type, ipv6_src, ipv6_dst,
                                 ether_src, ether_dst)
   -- TODO: decrement the IPv4 ttl as this is part of forwarding
   -- TODO: do not encapsulate if ttl was already 0; send icmp
   if debug then print("ipv6", ipv6_src, ipv6_dst) end

   -- As if it were Ethernet decapsulated.
   local offset = lwstate.l2_size
   local payload_length = pkt.length - offset
   local dscp_and_ecn = pkt.data[offset + constants.o_ipv4_dscp_and_ecn]
   -- Make room at the beginning for IPv6 header.
   packet.shiftright(pkt, constants.ipv6_fixed_header_size)
   -- Modify Ethernet header.
   local eth_type = constants.n_ethertype_ipv6
   write_eth_header(pkt.data, ether_src, ether_dst, eth_type, lwstate.v6_vlan_tag)

   -- Modify IPv6 header.
   write_ipv6_header(pkt.data + lwstate.l2_size, ipv6_src, ipv6_dst,
                     dscp_and_ecn, next_hdr_type, payload_length)

   if pkt.length - lwstate.l2_size <= lwstate.ipv6_mtu then
      if debug then
         print("encapsulated packet:")
         lwdebug.print_pkt(pkt)
      end
      guarded_transmit(pkt, lwstate.o6)
      return
   end

   -- Otherwise, fragment if possible
   local unfrag_header_size = lwstate.l2_size + constants.ipv6_fixed_header_size
   local flags = pkt.data[unfrag_header_size + constants.o_ipv4_flags]
   if band(flags, 0x40) == 0x40 then -- The Don't Fragment bit is set
      -- According to RFC 791, the original packet must be discarded.
      -- Return a packet with ICMP(3, 4) and the appropriate MTU
      -- as per https://tools.ietf.org/html/rfc2473#section-7.2
      if debug then lwdebug.print_pkt(pkt) end
      -- The source address of the packet is where the ICMP packet should be sent
      local o_src = lwstate.l2_size + constants.o_ipv4_src_addr
      local dst_ip = pkt.data + constants.ipv6_fixed_header_size + o_src
      local icmp_config = {type = constants.icmpv4_dst_unreachable,
                           code = constants.icmpv4_datagram_too_big_df,
                           extra_payload_offset = constants.ipv6_fixed_header_size,
                           next_hop_mtu = lwstate.ipv6_mtu - constants.ipv6_fixed_header_size,
                           vlan_tag = lwstate.v4_vlan_tag
                           }
      local icmp_pkt = icmp.new_icmpv4_packet(lwstate.aftr_mac_inet_side, lwstate.inet_mac,
                                              lwstate.aftr_ipv4_ip, dst_ip, pkt,
                                              lwstate.l2_size, icmp_config)
      packet.free(pkt)
      guarded_transmit(icmp_pkt, lwstate.o4)
      return
   end

   -- DF wasn't set; fragment the large packet
   local pkts = fragmentv6.fragment_ipv6(pkt, unfrag_header_size, lwstate.l2_size, lwstate.ipv6_mtu)
   if debug and pkts then
      print("Encapsulated packet into fragments")
      for idx,fpkt in ipairs(pkts) do
         print(string.format("    Fragment %i", idx))
         lwdebug.print_pkt(fpkt)
      end
   end
   for i=1,#pkts do
      guarded_transmit(pkts[i], lwstate.o6)
   end
end

local function icmpv4_incoming(lwstate, pkt)
   local ipv4_header_size = get_ihl_from_offset(pkt, lwstate.l2_size)
   local icmp_base = lwstate.l2_size + ipv4_header_size
   local ip_base = icmp_base + constants.icmp_base_size
   local icmp_type_offset = icmp_base -- it's the zeroeth byte of the ICMP header
   local icmp_type = pkt.data[icmp_type_offset]
   local source_port, ipv4_dst

   -- RFC 7596 is silent on whether to validate echo request/reply checksums.
   -- ICMP checksums SHOULD be validated according to RFC 5508.
   -- Choose to verify the echo reply/request ones too.
   -- Note: the lwaftr SHOULD NOT validate the transport checksum of the embedded packet.
   -- Were it to nonetheless do so, RFC 4884 extension headers MUST NOT
   -- be taken into account when validating the checksum
   local o_tl = lwstate.l2_size + constants.o_ipv4_total_length
   local icmp_bytes = C.ntohs(rd16(pkt.data + o_tl)) - ipv4_header_size
   if checksum.ipsum(pkt.data + icmp_base, icmp_bytes, 0) ~= 0 then
      packet.free(pkt)
      return -- Silently drop the packet, as per RFC 5508
   end

   -- checksum was ok
   if icmp_type == constants.icmpv4_echo_reply or icmp_type == constants.icmpv4_echo_request then
      source_port = C.ntohs(rd16(pkt.data + icmp_base + constants.o_icmpv4_echo_identifier))
      -- Use the outermost IP header for the destination; it's not repeated in the payload
      ipv4_dst = rd32(pkt.data + lwstate.l2_size + constants.o_ipv4_dst_addr)
   else
      -- source port is the zeroeth byte of an encapsulated tcp or udp packet
      -- TODO: explicitly check for tcp/udp?
      -- As per REQ-3, use the ip address embedded in the ICMP payload
      -- The Internet Header Length is the low 4 bits, in 32-bit words; convert it to bytes
      local embedded_ipv4_header_size = bit.band(pkt.data[ip_base + constants.o_ipv4_ver_and_ihl], 0xf) * 4
      local o_sp = ip_base + embedded_ipv4_header_size
      source_port = C.ntohs(rd16(pkt.data + o_sp))
      local o_ip = ip_base + constants.o_ipv4_src_addr
      ipv4_dst = rd32(pkt.data + o_ip)
   end
   -- IPs are stored in network byte order in the binding table
   local ipv6_dst, ipv6_src = binding_lookup_ipv4(lwstate, ipv4_dst, source_port)
   if not ipv6_dst then
      -- No match found in the binding table; the packet MUST be discarded
      packet.free(pkt)
      return
   end
   -- Otherwise, the packet MUST be forwarded
   local next_hdr = constants.proto_ipv4
   return ipv6_encapsulate(lwstate, pkt, next_hdr, ipv6_src, ipv6_dst,
                           lwstate.aftr_mac_b4_side, lwstate.b4_mac)
end


local function key_ipv4_frag(lwstate, frag)
   local frag_id = rd16(frag.data + lwstate.l2_size + constants.o_ipv4_identification)
   local src_ip = fstring(frag.data + lwstate.l2_size + constants.o_ipv4_src_addr, 4)
   local dst_ip = fstring(frag.data + lwstate.l2_size + constants.o_ipv4_dst_addr, 4)
   return frag_id .. "|" .. src_ip .. dst_ip
end

local function cache_ipv4_fragment(lwstate, frag)
   local cache = lwstate.fragment4_cache
   local key = key_ipv4_frag(lwstate, frag)
   cache[key] = cache[key] or {}
   table.insert(cache[key], frag)
   return cache[key]
end

local function clean_ipv4_fragment_cache(lwstate, frags)
   local key = key_ipv4_frag(lwstate, frags[1])
   lwstate.fragment4_cache[key] = nil
   for _, p in ipairs(frags) do
      packet.free(p)
   end
end


-- The incoming packet is a complete one with ethernet headers.
local function from_inet(lwstate, pkt)
   if fragmentv4.is_ipv4_fragment(pkt, lwstate.l2_size) then
      local frags = cache_ipv4_fragment(lwstate, pkt)
      local frag_status, maybe_pkt = fragmentv4.reassemble_ipv4(frags, lwstate.l2_size)
      if frag_status == fragmentv4.REASSEMBLE_MISSING_FRAGMENT then
         return -- Nothing useful to be done yet
      elseif frag_status == fragmentv4.REASSEMBLE_INVALID then
         if maybe_pkt then -- This is an ICMP packet
            clean_ipv4_fragment_cache(lwstate, frags)
            if lwstate.policy_icmpv4_outgoing == lwconf.policies["DROP"] then
               packet.free(maybe_pkt)
            else
               guarded_transmit(maybe_pkt, lwstate.o4)
            end
         end
         return
      else -- Reassembly was successful
         clean_ipv4_fragment_cache(lwstate, frags)
         if debug then lwdebug.print_pkt(maybe_pkt) end
         pkt = maybe_pkt -- Do the rest of the processing on the reassembled packet
      end
   end

   -- Check incoming ICMP -first-, because it has different binding table lookup logic
   -- than other protocols.
   local proto_offset = lwstate.l2_size + constants.o_ipv4_proto
   local proto = pkt.data[proto_offset]
   if proto == constants.proto_icmp then
      if lwstate.policy_icmpv4_incoming == lwconf.policies['DROP'] then
         packet.free(pkt)
         return
      else
         return icmpv4_incoming(lwstate, pkt)
      end
   end

   -- It's not incoming ICMP; back to regular processing
   local ipv6_dst, ipv6_src = binding_lookup_dst_ipv4_from_pkt(lwstate, pkt, lwstate.l2_size)
   if not ipv6_dst then
      if debug then print("lookup failed") end
      if lwstate.policy_icmpv4_outgoing == lwconf.policies['DROP'] then
         packet.free(pkt)
         return -- lookup failed
      else
         local src_ip_start = lwstate.l2_size + constants.o_ipv4_src_addr
         local to_ip = pkt.data + src_ip_start
         return icmp_after_discard(lwstate, pkt, to_ip)-- ICMPv4 type 3 code 1 (dst/host unreachable)
      end
   end

   local ether_src = lwstate.aftr_mac_b4_side
   local ether_dst = lwstate.b4_mac -- FIXME: this should probaby use NDP

   -- Do not encapsulate packets that now have a ttl of zero or wrapped around
   local ttl = decrement_ttl(lwstate, pkt)
   if ttl == 0 or ttl == 255 then
      if lwstate.policy_icmpv4_outgoing == lwconf.policies['DROP'] then
         return
      end
      local o_src = lwstate.l2_size + constants.o_ipv4_src_addr
      local dst_ip = pkt.data + o_src
      local icmp_config = {type = constants.icmpv4_time_exceeded,
                           code = constants.icmpv4_ttl_exceeded_in_transit,
                           vlan_tag = lwstate.v4_vlan_tag
                           }
      local ttl0_icmp =  icmp.new_icmpv4_packet(lwstate.aftr_mac_inet_side, lwstate.inet_mac,
                                                lwstate.aftr_ipv4_ip, dst_ip, pkt,
                                                lwstate.l2_size, icmp_config)
      guarded_transmit(ttl0_icmp, lwstate.o4)
      return
   end

   local next_hdr = constants.proto_ipv4
   return ipv6_encapsulate(lwstate, pkt, next_hdr, ipv6_src, ipv6_dst,
                           ether_src, ether_dst)
end

local function tunnel_packet_too_big(lwstate, pkt)
   local ipv6_hs = constants.ipv6_fixed_header_size
   local eth_hs = lwstate.l2_size
   local icmp_hs = constants.icmp_base_size
   local orig_packet_offset = eth_hs + ipv6_hs + icmp_hs + ipv6_hs

   local next_hop_mtu_offset = 6
   local o_mtu = eth_hs + ipv6_hs + next_hop_mtu_offset
   local specified_mtu = C.ntohs(rd16(pkt.data + o_mtu))
   local icmp_config = {type = constants.icmpv4_dst_unreachable,
                        code = constants.icmpv4_datagram_too_big_df,
                        extra_payload_offset = orig_packet_offset - eth_hs,
                        next_hop_mtu = specified_mtu - constants.ipv6_fixed_header_size,
                        vlan_tag = lwstate.v4_vlan_tag,
                        }
   local o_src = orig_packet_offset + constants.o_ipv4_src_addr
   local dst_ip = pkt.data + o_src
   local icmp_reply = icmp.new_icmpv4_packet(lwstate.aftr_mac_inet_side, lwstate.inet_mac,
                                             lwstate.aftr_ipv4_ip, dst_ip, pkt,
                                             lwstate.l2_size, icmp_config)
   return icmp_reply
end

-- This is highly redundant code, but it avoids conditionals
local function tunnel_generic_unreachable(lwstate, pkt)
   local ipv6_hs = constants.ipv6_fixed_header_size
   local eth_hs = lwstate.l2_size
   local icmp_hs = constants.icmp_base_size
   local orig_packet_offset = eth_hs + ipv6_hs + icmp_hs + ipv6_hs
   local icmp_config = {type = constants.icmpv4_dst_unreachable,
                        code = constants.icmpv4_host_unreachable,
                        extra_payload_offset = orig_packet_offset - eth_hs,
                        vlan_tag = lwstate.v4_vlan_tag
                        }
   local o_src = orig_packet_offset + constants.o_ipv4_src_addr
   local dst_ip = pkt.data + o_src
   local icmp_reply = icmp.new_icmpv4_packet(lwstate.aftr_mac_inet_side, lwstate.inet_mac,
                                             lwstate.aftr_ipv4_ip, dst_ip, pkt,
                                             lwstate.l2_size, icmp_config)
   return icmp_reply
end

local function icmpv6_incoming(lwstate, pkt)
   local icmpv6_offset = lwstate.l2_size + constants.ipv6_fixed_header_size
   local icmp_type = pkt.data[icmpv6_offset]
   local icmp_code = pkt.data[icmpv6_offset + 1]
   local icmpv4_reply
   if icmp_type == constants.icmpv6_packet_too_big then
      if icmp_code ~= constants.icmpv6_code_packet_too_big then
         return -- Invalid code
      end
      icmpv4_reply = tunnel_packet_too_big(lwstate, pkt)

   -- Take advantage of having already checked for 'packet too big' (2), and
   -- unreachable node/hop limit exceeded/paramater problem being 1, 3, 4 respectively
   elseif icmp_type <= constants.icmpv6_parameter_problem then
      -- If the time limit was exceeded, require it was a hop limit code
      if icmp_type == constants.icmpv6_time_limit_exceeded then
         if icmp_code ~= constants.icmpv6_hop_limit_exceeded then
            return
         end
      end
      -- Accept all unreachable or parameter problem codes
      icmpv4_reply = tunnel_generic_unreachable(lwstate, pkt)
   else -- No other types of ICMPv6, including echo request/reply, are handled
      return
   end

   -- There's an ICMPv4 packet. If it's in response to a packet from the external
   -- network, send it there. If hairpinning is/was enabled, it could be from a
   -- b4; if it was from a b4, encapsulate the generated IPv4 message and send it.
   -- This is the most plausible reading of RFC 2473, although not unambigous.
   local first_ipv4_header_bytes = get_ihl_from_offset(icmpv4_reply, lwstate.l2_size)
   local pre_embed_ipv4_bytes = lwstate.l2_size + first_ipv4_header_bytes + constants.icmp_base_size
   local ipv6_dst = binding_lookup_src_ipv4_from_pkt(lwstate, icmpv4_reply, pre_embed_ipv4_bytes)
   if ipv6_dst and lwstate.hairpinning then
      if debug then print("Hairpinning ICMPv4 mapped from ICMPv6") end
      -- Hairpinning was implicitly allowed now or in the recent past if the
      -- binding table lookup succeeded. Nonetheless, require that it be
      -- currently true to encapsulate and hairpin the outgoing packet.
      -- If it's false, send it out through the normal internet interface,
      -- like notifications to any non-bound host.
      return icmpv4_incoming(lwstate, icmpv4_reply) -- to B4
   else
      guarded_transmit(icmpv4_reply, lwstate.o4)
   end
end

local function get_ipv6_src_ip(lwstate, pkt)
   local ipv6_src = lwstate.l2_size + constants.o_ipv6_src_addr
   return fstring(pkt.data + ipv6_src, 16)
end

local function get_ipv6_dst_ip(lwstate, pkt)
   local ipv6_dst = lwstate.l2_size + constants.o_ipv6_dst_addr
   return fstring(pkt.data + ipv6_dst, 16)
end

local function key_ipv6_frag(lwstate, frag)
   local frag_id = fragmentv6.get_ipv6_frag_id(frag, lwstate.l2_size)
   local src_ip = get_ipv6_src_ip(lwstate, frag)
   local dst_ip = get_ipv6_dst_ip(lwstate, frag)
   local src_dst = src_ip..dst_ip
   return frag_id .. '|' .. src_dst
end

local function cache_ipv6_fragment(lwstate, frag)
   local cache = lwstate.fragment6_cache
   local key = key_ipv6_frag(lwstate, frag)
   cache[key] = cache[key] or {}
   table.insert(cache[key], frag)
   return cache[key]
end

local function clean_ipv6_fragment_cache(lwstate, frags)
   local key = key_ipv6_frag(lwstate, frags[1])
   lwstate.fragment6_cache[key] = nil
   for i=1,#frags do
      packet.free(frags[i])
   end
end

local function from_b4(lwstate, pkt)
   -- TODO: only send ICMP on failure for packets that plausibly would be bound?
   if fragmentv6.is_ipv6_fragment(pkt, lwstate.l2_size) then
      local frags = cache_ipv6_fragment(lwstate, pkt)
      local frag_status, maybe_pkt = fragmentv6.reassemble_ipv6(frags, lwstate.l2_size)
      if frag_status == fragmentv6.FRAGMENT_MISSING then
           return -- Nothing useful to be done yet
      elseif frag_status == fragmentv6.REASSEMBLY_INVALID then
         if maybe_pkt then -- This is an ICMP packet
            clean_ipv6_fragment_cache(lwstate, frags)
            if lwstate.policy_icmpv6_outgoing == lwconf.policies['DROP'] then
               packet.free(maybe_pkt)
            else
               guarded_transmit(maybe_pkt, lwstate.o6)
            end
            return
         end
      else -- It was successfully reassembled
         -- The spec mandates that reassembly must occur before decapsulation
         clean_ipv6_fragment_cache(lwstate, frags)
         if debug then lwdebug.print_pkt(maybe_pkt) end
         pkt = maybe_pkt -- do the rest of the processing on the reassembled packet
      end
   end

   local proto_offset = lwstate.l2_size + constants.o_ipv6_next_header
   local proto = pkt.data[proto_offset]
   if proto == constants.proto_icmpv6 then
      if lwstate.policy_icmpv6_incoming == lwconf.policies['DROP'] then
         packet.free(pkt)
         return
      else
         return icmpv6_incoming(lwstate, pkt)
      end
   end

   -- check src ipv4, ipv6, and port against the binding table
   local ipv6_src_ip_offset = lwstate.l2_size + constants.o_ipv6_src_addr
   local ipv6_dst_ip_offset = lwstate.l2_size + constants.o_ipv6_dst_addr
   -- FIXME: deal with multiple IPv6 headers?
   local eth_and_ipv6 = lwstate.l2_size + constants.ipv6_fixed_header_size
   local ipv4_src_ip_offset = eth_and_ipv6 + constants.o_ipv4_src_addr
   -- FIXME: as above + non-tcp/non-udp payloads
   local ipv4_src_port_offset = eth_and_ipv6 + get_ihl_from_offset(pkt, eth_and_ipv6)
   local ipv6_src_ip = pkt.data + ipv6_src_ip_offset
   local ipv6_dst_ip = pkt.data + ipv6_dst_ip_offset
   local ipv4_src_ip = rd32(pkt.data + ipv4_src_ip_offset)
   local ipv4_src_port = C.ntohs(rd16(pkt.data + ipv4_src_port_offset))

   if in_binding_table(lwstate, ipv6_src_ip, ipv6_dst_ip, ipv4_src_ip, ipv4_src_port) then
      -- Is it worth optimizing this to change src_eth, src_ipv6, ttl, checksum,
      -- rather than decapsulating + re-encapsulating? It would be faster, but more code.
      local offset = lwstate.l2_size + constants.ipv6_fixed_header_size
      if debug then
         print("lwstate.hairpinning is", lwstate.hairpinning)
         print("binding_lookup...", binding_lookup_dst_ipv4_from_pkt(lwstate, pkt, offset))
      end
      if lwstate.hairpinning and ipv4_dst_in_binding_table(lwstate, pkt, offset) then
         -- Remove IPv6 header.
         packet.shiftleft(pkt, constants.ipv6_fixed_header_size)
         write_eth_header(pkt.data, lwstate.b4_mac, lwstate.aftr_mac_b4_side,
                          constants.n_ethertype_ipv4, lwstate.v4_vlan_tag)
         -- TODO:  refactor so this doesn't actually seem to be from the internet?
         return from_inet(lwstate, pkt)
      else
         -- Remove IPv6 header.
         packet.shiftleft(pkt, constants.ipv6_fixed_header_size)
         write_eth_header(pkt.data, lwstate.aftr_mac_inet_side, lwstate.inet_mac,
                          constants.n_ethertype_ipv4, lwstate.v4_vlan_tag)
         -- Fragment if necessary
         if pkt.length - lwstate.l2_size > lwstate.ipv4_mtu then
            local fragstatus, frags = fragmentv4.fragment_ipv4(pkt, lwstate.l2_size, lwstate.ipv4_mtu)
            if fragstatus == fragmentv4.FRAGMENT_OK then
               for i=1,#frags do
                  guarded_transmit(frags[i], lwstate.o4)
               end
               return
            else
               -- TODO: send ICMPv4 info if allowed by policy
               packet.free(pkt)
               return
            end
         else -- No fragmentation needed
            guarded_transmit(pkt, lwstate.o4)
            return
         end
      end
   elseif lwstate.policy_icmpv6_outgoing == lwconf.policies['ALLOW'] then
      icmp_b4_lookup_failed(lwstate, pkt, ipv6_src_ip)
      packet.free(pkt)
   else
      packet.free(pkt)
      return
   end
end

-- Modify the given packet in-place, and forward it, drop it, or reply with
-- an ICMP or ICMPv6 packet as per the internet draft and configuration policy.

-- Check each input device. Handle transmission through the system in the following
-- loops; handle unusual cases (ie, ICMP going through the same interface as it
-- was received from) where they occur.
function LwAftr:push ()
   local i4, i6 = self.input.v4, self.input.v6
   local o4, o6 = self.output.v4, self.output.v6
   self.o4, self.o6 = o4, o6

   -- If we are really slammed and can't keep up, packets are going to
   -- drop one way or another.  The nwritable() check is just to prevent
   -- us from burning the CPU on packets that we're pretty sure would be
   -- dropped anyway, so that when we're in an overload situation things
   -- don't get worse as the traffic goes up.  It's not a fool-proof
   -- check that we in fact will be able to successfully handle the
   -- packet, given that the packet might require fragmentation,
   -- hairpinning, or ICMP error messages, all of which might result in
   -- transmission of packets on the "other" interface or multiple
   -- packets on the "right" interface.

   for _=1,math.min(link.nreadable(i4), link.nwritable(o6)) do
      local pkt = receive(i4)
      if debug then print("got a pkt") end
      -- Keep the ethertype in network byte order
      local ethertype = rd16(pkt.data + self.o_ethernet_ethertype)

      if ethertype == constants.n_ethertype_ipv4 then -- Incoming packet from the internet
         from_inet(self, pkt)
      else
         packet.free(pkt)
      end -- Silently drop all other types coming from the internet interface
   end

   for _=1,math.min(link.nreadable(i6), link.nwritable(o4)) do
      local pkt = receive(i6)
      if debug then print("got a pkt") end
      local ethertype = rd16(pkt.data + self.o_ethernet_ethertype)
      if ethertype == constants.n_ethertype_ipv6 then
         -- decapsulate iff the source was a b4, and forward/hairpin/ICMPv6 as needed
         from_b4(self, pkt)
      else
         packet.free(pkt)
      end -- FIXME: silently drop other types; is this the right thing to do?
   end
end
