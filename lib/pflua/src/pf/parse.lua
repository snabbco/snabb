module(...,package.seeall)

allow_address_of = true

local utils = require('pf.utils')
local constants = require('pf.constants')

local ipv4_to_int, ipv6_as_4x32 = utils.ipv4_to_int, utils.ipv6_as_4x32
local uint32 = utils.uint32

local function skip_whitespace(str, pos)
   while pos <= #str and str:match('^%s', pos) do
      pos = pos + 1
   end
   return pos
end

local function set(...)
   local ret = {}
   for k, v in pairs({...}) do ret[v] = true end
   return ret
end

local punctuation = set(
   '(', ')', '[', ']', ':', '!', '!=', '<', '<=', '>', '>=', '=', '==',
   '+', '-', '*', '/', '&', '|', '^', '&&', '||', '<<', '>>', '\\'
)

local number_terminators = " \t\r\n)]:!<>=+-*/%&|^"

local function lex_number(str, pos, base)
   local res = 0
   local i = pos
   while i <= #str do
      local chr = str:sub(i,i)
      local n = tonumber(chr, base)
      if n then
         res = res * base + n
         i = i + 1
      elseif not number_terminators:find(chr, 1, true) then
         return nil
      else
         break
      end
   end

   if i == pos then
      -- No digits parsed, can happen when lexing "0x" or "09".
      return nil
   end
   return res, i  -- EOS or end of number.
end

local function maybe_lex_number(str, pos)
   if str:match("^0x", pos) then
      return "hexadecimal", lex_number(str, pos+2, 16)
   elseif str:match("^0%d", pos) then
      return "octal", lex_number(str, pos+1, 8)
   elseif str:match("^%d", pos) then
      return "decimal", lex_number(str, pos, 10)
   end
end

local function lex_host_or_keyword(str, pos)
   local name, next_pos = str:match("^([%w.-]+)()", pos)
   assert(name, "failed to parse hostname or keyword at "..pos)
   assert(name:match("^%w", 1, 1), "bad hostname or keyword "..name)
   assert(name:match("^%w", #name, #name), "bad hostname or keyword "..name)

   local kind, number, number_next_pos = maybe_lex_number(str, pos)
   -- Only interpret name as a number as a whole.
   if number and number_next_pos == next_pos then
      assert(number <= 0xffffffff, 'integer too large: '..name)
      return number, next_pos
   else
      return name, next_pos
   end
end

local function lex_ipv4(str, pos)
   local function lex_byte(str)
      local byte = tonumber(str, 10)
      if byte >= 256 then return nil end
      return byte
   end
   local digits, dot = str:match("^(%d%d?%d?)()", pos)
   if not digits then return nil end
   local addr = { 'ipv4' }
   local byte = lex_byte(digits)
   if not byte then return nil end
   table.insert(addr, byte)
   pos = dot
   for i=1,3 do
      local digits, dot = str:match("^%.(%d%d?%d?)()", pos)
      if not digits then break end
      local byte = lex_byte(digits)
      if not byte then return nil end
      table.insert(addr, byte)
      pos = dot
   end

   local last_char = str:sub(pos, pos)
   -- IPv4 address is actually a hostname
   if last_char:match("[%w.-]") then return nil end

   local terminators = " \t\r\n)/"
   assert(pos > #str or terminators:find(last_char, 1, true),
          "unexpected terminator for ipv4 address")
   return addr, pos
end

local function lex_ipv6(str, pos)
   local addr = { 'ipv6' }
   local hole_index

   if str:sub(pos, pos + 1) == "::" then
      hole_index = 2
      pos = pos + 2
   end

   local after_sep = false
   local digits_pattern = "^(%x%x?%x?%x?)()"
   local expected_sep = ":"
   local ipv4_fields = 0

   while true do
      local digits, next_pos = str:match(digits_pattern, pos)
      if not digits then
         if after_sep then
            error("wrong IPv6 address")
         else
            break
         end
      end

      local sep = str:sub(next_pos, next_pos)
      if sep == "." and expected_sep == ":" then
         expected_sep = "."
         digits_pattern = "^(%d%d?%d?)()"
         -- Continue loop without advancing pos.
         -- Will parse field as decimal in the next iteration.
      else
         pos = next_pos

         if expected_sep == ":" then
            table.insert(addr, tonumber(digits, 16))
         else
            local ipv4_field = tonumber(digits, 10)
            assert(ipv4_field < 255, "wrong IPv6 address")
            ipv4_fields = ipv4_fields + 1
            if ipv4_fields % 2 == 0 then
               addr[#addr] = addr[#addr] * 256 + ipv4_field
            else
               table.insert(addr, ipv4_field)
            end
         end

         if sep ~= expected_sep then break end
         pos = pos + 1
         if sep == ":" and not hole_index and str:sub(pos, pos) == ":" then
            pos = pos + 1
            hole_index = #addr + 1
            after_sep = false
         else
            after_sep = true
         end
      end
   end

   assert(ipv4_fields == 0 or ipv4_fields == 4, "wrong IPv6 address")

   if hole_index then
      local zeros = 9 - #addr
      assert(zeros >= 1, "wrong IPv6 address")
      for i=1,zeros do
         table.insert(addr, hole_index, 0)
      end
   end

   assert(#addr == 9, "wrong IPv6 address")

   local terminators = " \t\r\n)/"
   assert(pos > #str or terminators:find(str:sub(pos, pos), 1, true),
          "unexpected terminator for ipv6 address")

   return addr, pos
end

local function lex_ehost(str, pos)
   local start = pos
   local addr = { 'ehost' }
   local digits, dot = str:match("^(%x%x?)()%:", pos)
   assert(digits, "failed to parse ethernet host address at "..pos)
   table.insert(addr, tonumber(digits, 16))
   pos = dot
   for i=1,5 do
      local digits, dot = str:match("^%:(%x%x?)()", pos)
      assert(digits, "failed to parse ethernet host address at "..pos)
      table.insert(addr, tonumber(digits, 16))
      pos = dot
   end
   local terminators = " \t\r\n)/"
   local last_char = str:sub(pos, pos)
   -- MAC address is actually an IPv6 address
   if last_char == ':' or last_char == '.' then return nil, start end
   assert(pos > #str or terminators:find(last_char, 1, true),
          "unexpected terminator for ethernet host address")
   return addr, pos
end

local function lex_addr_or_host(str, pos)
   if str:match('^%x%x?:%x%x?:%x%x?:%x%x?:%x%x?:%x%x?', pos) then
      local result, pos = lex_ehost(str, pos)
      if result then return result, pos end
      return lex_ipv6(str, pos)
   elseif str:match("^%x?%x?%x?%x?%:", pos) then
      return lex_ipv6(str, pos)
   elseif str:match("^%d%d?%d?", pos) then
      local result, pos = lex_ipv4(str, pos)
      if result then return result, pos end  -- Fall through.
   end

   return lex_host_or_keyword(str, pos)
end

local function lex(str, pos, opts)
   -- EOF.
   if pos > #str then return nil, pos end

   if opts.address then
      -- Net addresses.
      return lex_addr_or_host(str, pos)
   end

   -- Non-alphanumeric tokens.
   local two = str:sub(pos,pos+1)
   if punctuation[two] then return two, pos+2 end
   local one = str:sub(pos,pos)
   if punctuation[one] then return one, pos+1 end

   -- Numeric literals.
   if opts.maybe_arithmetic then
      local kind, number, next_pos = maybe_lex_number(str, pos)
      if kind then
         assert(number, "unexpected end of "..kind.." literal at "..pos)
         assert(number <= 0xffffffff, 'integer too large: '..str:sub(pos, next_pos-1))
         return number, next_pos
      end
   end

   -- "len" is the only bare name that can appear in an arithmetic
   -- expression.  "len-1" lexes as { 'len', '-', 1 } in arithmetic
   -- contexts, but { "len-1" } otherwise.
   if opts.maybe_arithmetic and str:match("^len", pos) then
      if pos + 3 > #str or not str:match("^[%w.]", pos+3) then
         return 'len', pos+3
      end
   end

   return lex_host_or_keyword(str, pos)
end

local function tokens(str)
   local pos, next_pos = 1, nil
   local peeked = nil
   local peeked_address = nil
   local peeked_maybe_arithmetic = nil
   local last_pos = 0
   local primitive_error = error
   local function peek(opts)
      opts = opts or {}
      if not next_pos or opts.address ~= peeked_address or
            opts.maybe_arithmetic ~= peeked_maybe_arithmetic then
         pos = skip_whitespace(str, pos)
         peeked, next_pos = lex(str, pos, opts or {})
         peeked_address = opts.address
         peeked_maybe_arithmetic = opts.maybe_arithmetic
         assert(next_pos, "next pos is nil")
      end
      return peeked
   end
   local function next(opts)
      local tok = assert(peek(opts), "unexpected end of filter string")
      pos, next_pos = next_pos, nil
      last_pos = pos
      return tok
   end
   local function consume(expected, opts)
      local tok = next(opts)
      assert(tok == expected, "expected "..expected..", got: "..tok)
   end
   local function check(expected, opts)
      if peek(opts) ~= expected then return false end
      next()
      return true
   end
   local function error_str(message, ...)
      local location_error_message = "Pflua parse error: In expression \"%s\""
      local start = #location_error_message - 4
      local cursor_pos = start + last_pos

      local result = "\n"
      result = result..location_error_message:format(str).."\n"
      result = result..string.rep(" ", cursor_pos).."^".."\n"
      result = result..message:format(...).."\n"
      return result
   end
   local function error(message, ...)
       primitive_error(error_str(message, ...))
   end
   return { peek = peek, next = next, consume = consume, check = check, error = error }
end

local addressables = set(
   'arp', 'rarp', 'wlan', 'ether', 'fddi', 'tr', 'ppp',
   'slip', 'link', 'radio', 'ip', 'ip6', 'tcp', 'udp', 'icmp',
   'igmp', 'pim', 'igrp', 'vrrp', 'sctp'
)

local function nullary()
   return function(lexer, tok)
      return { tok }
   end
end

local function unary(parse_arg)
   return function(lexer, tok)
      return { tok, parse_arg(lexer) }
   end
end

function parse_host_arg(lexer)
   local arg = lexer.next({address=true})
   if type(arg) == 'string' or arg[1] == 'ipv4' or arg[1] == 'ipv6' then
      return arg
   end
   lexer.error('ethernet address used in non-ether expression')
end

function parse_int_arg(lexer, max_len)
   local ret = lexer.next({maybe_arithmetic=true})
   assert(type(ret) == 'number', 'expected a number', ret)
   if max_len then assert(ret <= max_len, 'out of range '..ret) end
   return ret
end

function parse_uint16_arg(lexer) return parse_int_arg(lexer, 0xffff) end

function parse_net_arg(lexer)

   local function check_non_network_bits_in_ipv4(addr, mask_bits, mask_str)
      local ipv4 = uint32(addr[2], addr[3], addr[4], addr[5])
      if (bit.band(ipv4, mask_bits) ~= bit.tobit(ipv4)) then
         lexer.error("Non-network bits set in %s/%s",
            table.concat(addr, ".", 2), mask_str)
     end
   end

   local function check_non_network_bits_in_ipv6(addr, mask_len)
      local function format_ipv6(addr, mask_len)
         return string.format("%x:%x:%x:%x:%x:%x:%x:%x/%d, ",
            addr[2], addr[3], addr[4], addr[5], addr[5], addr[6], addr[7],
            addr[8], mask_len)
      end
      local ipv6 = ipv6_as_4x32(addr)
      for i, fragment in ipairs(ipv6) do
         local mask_len_fragment = mask_len > 32 and 32 or mask_len
         local mask_bits = 2^32 - 2^(32 - mask_len_fragment)
         if (bit.band(fragment, mask_bits) ~= bit.tobit(fragment)) then
            lexer.error("Non-network bits set in %s", format_ipv6(addr, mask_len))
         end
         mask_len = mask_len - mask_len_fragment
      end
   end

   local arg = lexer.next({address=true})
   if type(arg) ~= 'table' then
      lexer.error('named nets currently unsupported')
   elseif arg[1] == 'ehost' then
      lexer.error('ethernet address used in non-ether expression')
   end

   -- IPv4 dotted triple, dotted pair or bare net addresses
   if arg[1] == 'ipv4' and #arg < 5 then
      local mask_len = 32
      for i=#arg+1,5 do
         arg[i] = 0
         mask_len = mask_len - 8
      end
      return { 'ipv4/len', arg, mask_len }
   end
   if arg[1] == 'ipv4' or arg[1] == 'ipv6' then
      if lexer.check('/') then
         local mask_len = parse_int_arg(lexer, arg[1] == 'ipv4' and 32 or 128)
         if (arg[1] == 'ipv4') then
            local mask_bits = 2^32 - 2^(32 - mask_len)
            check_non_network_bits_in_ipv4(arg, mask_bits, tostring(mask_len))
         end
         if (arg[1] == 'ipv6') then
            check_non_network_bits_in_ipv6(arg, mask_len)
         end
         return { arg[1]..'/len', arg, mask_len }
      elseif lexer.check('mask') then
         if (arg[1] == 'ipv6') then
            lexer.error("Not valid syntax for IPv6")
         end
         local mask = lexer.next({address=true})
         if type(mask) ~= 'table' or mask[1] ~= 'ipv4' then
            lexer.error("Invalid IPv4 mask")
         end
         check_non_network_bits_in_ipv4(arg, ipv4_to_int(mask),
            table.concat(mask, '.', 2))
         return { arg[1]..'/mask', arg, mask }
      else
         return arg
      end
   end
end

local function to_port_number(tok)
   local port = tok
   if type(tok) == 'string' then
      local next_pos
      port, next_pos = lex_number(tok, 1, 10)
      if not port or next_pos ~= #tok+1 then
         -- Token is not a valid decimal literal, fallback to services.
         return constants.services[tok]
      end
   end

   assert(port <= 65535, 'port '..port..' out of range')
   return port
end

local function parse_port_arg(lexer)
   local tok = lexer.next()
   local result = to_port_number(tok)
   if not result then
      lexer.error('unsupported port %s', tok)
   end
   return result
end

local function parse_portrange_arg(lexer)
   local tok = lexer.next()

   -- Try to split portrange from start to first hyphen, or from start to
   -- second hyphen, and so on.
   local pos = 1
   while true do
      pos = tok:match("^%w+%-()", pos)
      if not pos then
         lexer.error('error parsing portrange %s', tok)
      end
      local from, to = to_port_number(tok:sub(1, pos - 2)), to_port_number(tok:sub(pos))
      if from and to then
         -- For libpcap compatibility, if to < from, swap them
         if from > to then from, to = to, from end
         return { from, to }
      end
   end
end

local function parse_ehost_arg(lexer)
   local arg = lexer.next({address=true})
   if type(arg) == 'string' or arg[1] == 'ehost' then
      return arg
   end
   lexer.error('invalid ethernet host %s', arg)
end

local function table_parser(table, default)
   return function (lexer, tok)
      local subtok = lexer.peek()
      if table[subtok] then
         lexer.consume(subtok)
         return table[subtok](lexer, tok..'_'..subtok)
      end
      if default then return default(lexer, tok) end
      lexer.error('unknown %s type %s ', tok, subtok)
   end
end

local ip_protos = set(
   'icmp', 'icmp6', 'igmp', 'igrp', 'pim', 'ah', 'esp', 'vrrp', 'udp', 'tcp', 'sctp'
)

local function parse_proto_arg(lexer, proto_type, protos)
   lexer.check('\\')
   local arg = lexer.next()
   if not proto_type then proto_type = 'ip' end
   if not protos then protos = ip_protos end
   if type(arg) == 'number' then return arg end
   if type(arg) == 'string' then
      local proto = arg:match("^(%w+)")
      if protos[proto] then return proto end
   end
   lexer.error('invalid %s proto %s', proto_type, arg)
end

local ether_protos = set(
   'ip', 'ip6', 'arp', 'rarp', 'atalk', 'aarp', 'decnet', 'sca', 'lat',
   'mopdl', 'moprc', 'iso', 'stp', 'ipx', 'netbeui'
)

local function parse_ether_proto_arg(lexer)
   return parse_proto_arg(lexer, 'ethernet', ether_protos)
end

local function parse_ip_proto_arg(lexer)
   return parse_proto_arg(lexer, 'ip', ip_protos)
end

local iso_protos = set('clnp', 'esis', 'isis')

local function parse_iso_proto_arg(lexer)
   return parse_proto_arg(lexer, 'iso', iso_protos)
end

local function simple_typed_arg_parser(expected)
   return function(lexer)
      local arg = lexer.next()
      if type(arg) == expected then return arg end
      lexer.error('expected a %s string, got %s', expected, type(arg))
   end
end

local parse_string_arg = simple_typed_arg_parser('string')

local function parse_decnet_host_arg(lexer)
   local arg = lexer.next({address=true})
   if type(arg) == 'string' then return arg end
   if arg[1] == 'ipv4' then
      arg[1] = 'decnet'
      assert(#arg == 3, "bad decnet address", arg)
      return arg
   end
   lexer.error('invalid decnet host %s', arg)
end

local llc_types = set(
   'i', 's', 'u', 'rr', 'rnr', 'rej', 'ui', 'ua',
   'disc', 'sabme', 'test', 'xis', 'frmr'
)

local function parse_llc(lexer, tok)
   if llc_types[lexer.peek()] then return { tok, lexer.next() } end
   return { tok }
end

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

local function parse_enum_arg(lexer, set)
   local arg = lexer.next()
   assert(set[arg], 'invalid argument: '..arg)
   return arg
end

local function enum_arg_parser(set)
   return function(lexer) return parse_enum_arg(lexer, set) end
end

local function parse_wlan_type(lexer, tok)
   local type = enum_arg_parser(wlan_frame_types)(lexer)
   if lexer.check('subtype') then
      local set
      if type == 'mgt' then set = wlan_frame_mgt_subtypes
      elseif type == 'mgt' then set = wlan_frame_ctl_subtypes
      else set = wlan_frame_data_subtypes end
      return { 'type', type, enum_arg_parser(set)(lexer) }
   end
   return { tok, type }
end

local function parse_wlan_subtype(lexer, tok)
   local subtype = lexer.next()
   assert(wlan_frame_mgt_subtypes[subtype]
             or wlan_frame_ctl_subtypes[subtype]
             or wlan_frame_data_subtypes[subtype],
          'bad wlan subtype '..subtype)
   return { tok, subtype }
end

local function parse_wlan_dir(lexer, tok)
   if (type(lexer.peek()) == 'number') then
      return { tok, lexer.next() }
   end
   return { tok, parse_enum_arg(lexer, wlan_directions) }
end

local function parse_optional_int(lexer, tok)
   if (type(lexer.peek()) == 'number') then
      return { tok, lexer.next() }
   end
   return { tok }
end

local src_or_dst_types = {
   host = unary(parse_host_arg),
   net = unary(parse_net_arg),
   port = unary(parse_port_arg),
   portrange = unary(parse_portrange_arg)
}

local ether_host_type = {
   host = unary(parse_ehost_arg)
}

local ether_types = {
   dst = table_parser(ether_host_type, unary(parse_ehost_arg)),
   src = table_parser(ether_host_type, unary(parse_ehost_arg)),
   host = unary(parse_ehost_arg),
   broadcast = nullary(),
   multicast = nullary(),
   proto = unary(parse_ether_proto_arg),
}

local ip_types = {
   dst = table_parser(src_or_dst_types, unary(parse_host_arg)),
   src = table_parser(src_or_dst_types, unary(parse_host_arg)),
   host = unary(parse_host_arg),
   proto = unary(parse_ip_proto_arg),
   protochain = unary(parse_ip_proto_arg),
   broadcast = nullary(),
   multicast = nullary(),
}

local ip6_types = {
   proto = unary(parse_ip_proto_arg),
   protochain = unary(parse_ip_proto_arg),
   broadcast = nullary(),
   multicast = nullary(),
}

local decnet_host_type = {
   host = unary(parse_decnet_host_arg),
}

local decnet_types = {
   src = table_parser(decnet_host_type, unary(parse_decnet_host_arg)),
   dst = table_parser(decnet_host_type, unary(parse_decnet_host_arg)),
   host = unary(parse_decnet_host_arg),
}

local wlan_types = {
   ra = unary(parse_ehost_arg),
   ta = unary(parse_ehost_arg),
   addr1 = unary(parse_ehost_arg),
   addr2 = unary(parse_ehost_arg),
   addr3 = unary(parse_ehost_arg),
   addr4 = unary(parse_ehost_arg),

   -- As an alias of 'ether'
   dst = table_parser(ether_host_type, unary(parse_ehost_arg)),
   src = table_parser(ether_host_type, unary(parse_ehost_arg)),
   host = unary(parse_ehost_arg),
   broadcast = nullary(),
   multicast = nullary(),
   proto = unary(parse_ether_proto_arg),
}

local iso_types = {
   proto = unary(parse_iso_proto_arg),
   ta = unary(parse_ehost_arg),
   addr1 = unary(parse_ehost_arg),
   addr2 = unary(parse_ehost_arg),
   addr3 = unary(parse_ehost_arg),
   addr4 = unary(parse_ehost_arg),
}

local tcp_or_udp_types = {
   port = unary(parse_port_arg),
   portrange = unary(parse_portrange_arg),
   dst = table_parser(src_or_dst_types),
   src = table_parser(src_or_dst_types),
}

local arp_types = {
   dst = table_parser(src_or_dst_types, unary(parse_host_arg)),
   src = table_parser(src_or_dst_types, unary(parse_host_arg)),
   host = unary(parse_host_arg),
}

local rarp_types = {
   dst = table_parser(src_or_dst_types, unary(parse_host_arg)),
   src = table_parser(src_or_dst_types, unary(parse_host_arg)),
   host = unary(parse_host_arg),
}

local parse_arithmetic

local function parse_addressable(lexer, tok)
   if not tok then
      tok = lexer.next({maybe_arithmetic=true})
      if not addressables[tok] then
         lexer.error('bad token while parsing addressable: %s', tok)
      end
   end
   lexer.consume('[')
   local pos = parse_arithmetic(lexer)
   local size = 1
   if lexer.check(':') then
      if lexer.check(1) then size = 1
      elseif lexer.check(2) then size = 2
      else lexer.consume(4); size = 4 end
   end
   lexer.consume(']')
   return { '['..tok..']', pos, size}
end

local function parse_primary_arithmetic(lexer, tok)
   tok = tok or lexer.next({maybe_arithmetic=true})
   if tok == '(' then
      local expr = parse_arithmetic(lexer)
      lexer.consume(')')
      return expr
   elseif tok == 'len' or type(tok) == 'number' then
      return tok
   elseif allow_address_of and tok == '&' then
      return { 'addr', parse_addressable(lexer) }
   elseif addressables[tok] then
      return parse_addressable(lexer, tok)
   else
      -- 'tok' may be a constant
      local val = constants.protocol_header_field_offsets[tok] or
                  constants.icmp_type_fields[tok] or
                  constants.tcp_flag_fields[tok]
      if val ~= nil then return val end
      lexer.error('bad token while parsing arithmetic expression %s', tok)
   end
end

local arithmetic_precedence = {
   ['*'] = 1, ['/'] = 1,
   ['+'] = 2, ['-'] = 2,
   ['<<'] = 3, ['>>'] = 3,
   ['&'] = 4,
   ['^'] = 5,
   ['|'] = 6
}

function parse_arithmetic(lexer, tok, max_precedence, parsed_exp)
   local exp = parsed_exp or parse_primary_arithmetic(lexer, tok)
   max_precedence = max_precedence or math.huge
   while true do
      local op = lexer.peek()
      local prec = arithmetic_precedence[op]
      if not prec or prec > max_precedence then return exp end
      lexer.consume(op)
      local rhs = parse_arithmetic(lexer, nil, prec - 1)
      exp = { op, exp, rhs }
   end
end

local primitives = {
   dst = table_parser(src_or_dst_types, unary(parse_host_arg)),
   src = table_parser(src_or_dst_types, unary(parse_host_arg)),
   host = unary(parse_host_arg),
   ether = table_parser(ether_types),
   fddi = table_parser(ether_types),
   tr = table_parser(ether_types),
   wlan = table_parser(wlan_types),
   broadcast = nullary(),
   multicast = nullary(),
   gateway = unary(parse_string_arg),
   net = unary(parse_net_arg),
   port = unary(parse_port_arg),
   portrange = unary(parse_portrange_arg),
   less = unary(parse_arithmetic),
   greater = unary(parse_arithmetic),
   ip = table_parser(ip_types, nullary()),
   ip6 = table_parser(ip6_types, nullary()),
   proto = unary(parse_proto_arg),
   tcp = table_parser(tcp_or_udp_types, nullary()),
   udp = table_parser(tcp_or_udp_types, nullary()),
   icmp = nullary(),
   icmp6 = nullary(),
   igmp = nullary(),
   igrp = nullary(),
   pim = nullary(),
   ah = nullary(),
   esp = nullary(),
   vrrp = nullary(),
   sctp = nullary(),
   protochain = unary(parse_proto_arg),
   arp = table_parser(arp_types, nullary()),
   rarp = table_parser(rarp_types, nullary()),
   atalk = nullary(),
   aarp = nullary(),
   decnet = table_parser(decnet_types, nullary()),
   iso = nullary(),
   stp = nullary(),
   ipx = nullary(),
   netbeui = nullary(),
   sca = nullary(),
   lat = nullary(),
   moprc = nullary(),
   mopdl = nullary(),
   llc = parse_llc,
   ifname = unary(parse_string_arg),
   on = unary(parse_string_arg),
   rnr = unary(parse_int_arg),
   rulenum = unary(parse_int_arg),
   reason = unary(enum_arg_parser(pf_reasons)),
   rset = unary(parse_string_arg),
   ruleset = unary(parse_string_arg),
   srnr = unary(parse_int_arg),
   subrulenum = unary(parse_int_arg),
   action = unary(enum_arg_parser(pf_actions)),
   type = parse_wlan_type,
   subtype = parse_wlan_subtype,
   dir = unary(enum_arg_parser(wlan_directions)),
   vlan = parse_optional_int,
   mpls = parse_optional_int,
   pppoed = nullary(),
   pppoes = parse_optional_int,
   iso = table_parser(iso_types, nullary()),
   clnp = nullary(),
   esis = nullary(),
   isis = nullary(),
   l1 = nullary(),
   l2 = nullary(),
   iih = nullary(),
   lsp = nullary(),
   snp = nullary(),
   csnp = nullary(),
   psnp = nullary(),
   vpi = unary(parse_int_arg),
   vci = unary(parse_int_arg),
   lane = nullary(),
   oamf4s = nullary(),
   oamf4e = nullary(),
   oamf4 = nullary(),
   oam = nullary(),
   metac = nullary(),
   bcc = nullary(),
   sc = nullary(),
   ilmic = nullary(),
   connectmsg = nullary(),
   metaconnect = nullary()
}

local function parse_primitive_or_arithmetic(lexer)
   local tok = lexer.next({maybe_arithmetic=true})
   if (type(tok) == 'number' or tok == 'len' or
       addressables[tok] and lexer.peek() == '[') then
      return parse_arithmetic(lexer, tok)
   end

   local parser = primitives[tok]
   if parser then return parser(lexer, tok) end

   -- At this point the official pcap grammar is squirrely.  It says:
   -- "If an identifier is given without a keyword, the most recent
   -- keyword is assumed.  For example, `not host vs and ace' is
   -- short for `not host vs and host ace` and which should not be
   -- confused with `not (host vs or ace)`."  For now we punt on this
   -- part of the grammar.
   local msg =
[[%s is not a recognized keyword. Likely causes:
a) %s is a typo, invalid keyword, or similar error.
b) You're trying to implicitly repeat the previous clause's keyword.
Instead of libpcap-style elision, explicitly use keywords in each clause:
ie, "host a and host b", not "host a and b".]]

   local err = string.format(msg, tok, tok)
   lexer.error(err)
end

local logical_ops = set('&&', 'and', '||', 'or')

local function is_arithmetic(exp)
   return (exp == 'len' or type(exp) == 'number' or
              exp[1]:match("^%[") or arithmetic_precedence[exp[1]])
end

local parse_logical

local function parse_logical_or_arithmetic(lexer, pick_first)
   local exp
   if lexer.peek() == 'not' or lexer.peek() == '!' then
      exp = { lexer.next(), parse_logical(lexer, true) }
   elseif lexer.check('(') then
      exp = parse_logical_or_arithmetic(lexer)
      lexer.consume(')')
   else
      exp = parse_primitive_or_arithmetic(lexer)
   end
   if is_arithmetic(exp) then
      if arithmetic_precedence[lexer.peek()] then
         exp = parse_arithmetic(lexer, nil, nil, exp)
      end
      if lexer.peek() == ')' then return exp end
      local op = lexer.next()
      assert(set('>', '<', '>=', '<=', '=', '!=', '==')[op],
             "expected a comparison operator, got "..op)
      -- Normalize == to =, because libpcap treats them identically
      if op == '==' then op = '=' end
      exp = { op, exp, parse_arithmetic(lexer) }
   end
   if pick_first then return exp end
   while true do
      local op = lexer.peek()
      if not op or op == ')' then return exp end
      local is_logical = logical_ops[op]
      if is_logical then
         lexer.consume(op)
      else
         -- The grammar is such that "tcp port 80" should actually
         -- parse as "tcp and port 80".
         op = 'and'
      end
      local rhs = parse_logical(lexer, true)
      exp = { op, exp, rhs }
   end
end

function parse_logical(lexer, pick_first)
   local expr = parse_logical_or_arithmetic(lexer, pick_first)
   assert(not is_arithmetic(expr), "expected a logical expression")
   return expr
end

function parse(str, opts)
   opts = opts or {}
   local lexer = tokens(str)
   local expr
   if opts.arithmetic then
      expr = parse_arithmetic(lexer)
   else
      if not lexer.peek({maybe_arithmetic=true}) then return { 'true' } end
      expr = parse_logical(lexer)
   end
   if lexer.peek() then error("unexpected token "..lexer.peek()) end
   return expr
end

function selftest ()
   print("selftest: pf.parse")
   local function check(expected, actual)
      assert(type(expected) == type(actual),
             "expected type "..type(expected).." but got "..type(actual))
      if type(expected) == 'table' then
         for k, v in pairs(expected) do check(v, actual[k]) end
      else
         assert(expected == actual, "expected "..expected.." but got "..actual)
      end
   end

   local function lex_test(str, elts, opts)
      local lexer = tokens(str)
      for i, val in ipairs(elts) do
         check(val, lexer.next(opts))
      end
      assert(not lexer.peek(opts), "more tokens, yo")
   end
   lex_test("ip", {"ip"}, {maybe_arithmetic=true})
   lex_test("len", {"len"}, {maybe_arithmetic=true})
   lex_test("len", {"len"}, {})
   lex_test("len-1", {"len-1"}, {})
   lex_test("len-1", {"len", "-", 1}, {maybe_arithmetic=true})
   lex_test("1-len", {1, "-", "len"}, {maybe_arithmetic=true})
   lex_test("1-len", {"1-len"}, {})
   lex_test("tcp port 80", {"tcp", "port", 80}, {})
   lex_test("tcp port 80 and (((ip[2:2] - ((ip[0]&0xf)<<2)) - ((tcp[12]&0xf0)>>2)) != 0)",
            { 'tcp', 'port', 80, 'and',
              '(', '(',
              '(',
              'ip', '[', 2, ':', 2, ']', '-',
              '(', '(', 'ip', '[', 0, ']', '&', 15, ')', '<<', 2, ')',
              ')',
              '-',
              '(', '(', 'tcp', '[', 12, ']', '&', 240, ')', '>>', 2, ')',
              ')', '!=', 0, ')'
            }, {maybe_arithmetic=true})
   lex_test("127.0.0.1", { { 'ipv4', 127, 0, 0, 1 } }, {address=true})
   lex_test("::", { { 'ipv6', 0, 0, 0, 0, 0, 0, 0, 0 } }, {address=true})
   lex_test("eee:eee:eee:eee:eee:eee:10.20.30.40",
            { { 'ipv6', 3822, 3822, 3822, 3822, 3822, 3822, 2580, 7720 } }, {address=true})
   lex_test("::10.20.30.40",
            { { 'ipv6', 0, 0, 0, 0, 0, 0, 2580, 7720 } }, {address=true})

   local function addr_error_test(str, expected_err)
      local lexer = tokens(str)
      local ok, actual_err = pcall(lexer.peek, {address=true})
      if not ok then
         if expected_err then
            assert(actual_err:find(expected_err, 1, true),
                   "expected error "..expected_err.." but got "..actual_err)
         end
      else
         error("expected error, got no error")
      end
   end
   addr_error_test("1:1:1::1:1:1:1:1", "wrong IPv6 address")
   addr_error_test("1:11111111", "wrong IPv6 address")
   addr_error_test("1::1:", "wrong IPv6 address")
   addr_error_test("1:2:3:4:5:6:7:1.2.3.4", "wrong IPv6 address")
   addr_error_test("1:2:3:4:5:1.2.3.4", "wrong IPv6 address")
   addr_error_test("1:2:3:4:5:1.2.3.4.5", "wrong IPv6 address")
   addr_error_test("1:2:3:4:5:6:1.2.3..", "wrong IPv6 address")
   addr_error_test("1:2:3:4:5:6:1.2.3.4.", "wrong IPv6 address")
   addr_error_test("1:2:3:4:5:6:1.2.3.300", "wrong IPv6 address")

   local function parse_test(str, elts) check(elts, parse(str)) end
   parse_test("",
              { 'true' })
   parse_test("host 127.0.0.1",
              { 'host', { 'ipv4', 127, 0, 0, 1 } })
   parse_test("host 1www.foo.com",
              { 'host', '1www.foo.com' })
   parse_test("host 999.foo.com",
              { 'host', '999.foo.com' })
   parse_test("host 200.foo.com",
              { 'host', '200.foo.com' })
   parse_test("host 1.2.3.4foo.com",
              { 'host', '1.2.3.4foo.com' })
   parse_test("host 1.2.3.4.5.com",
              { 'host', '1.2.3.4.5.com' })
   parse_test("host 0xffffffffffoo.com",
              { 'host', '0xffffffffffoo.com' })
   parse_test("host 0xffffffffff-oo.com",
              { 'host', '0xffffffffff-oo.com' })
   parse_test("src host 127.0.0.1",
              { 'src_host', { 'ipv4', 127, 0, 0, 1 } })
   parse_test("src 127.0.0.1",
              { 'src', { 'ipv4', 127, 0, 0, 1 } })
   parse_test("dst 1::ff11",
              { 'dst', { 'ipv6', 1, 0, 0, 0, 0, 0, 0, 65297 } })
   parse_test("src net 10.0.0.0/24",
              { 'src_net',
                { 'ipv4/len', { 'ipv4', 10, 0, 0, 0 }, 24 }})
   parse_test("ether proto rarp",
              { 'ether_proto', 'rarp' })
   parse_test("ether proto \\rarp",
              { 'ether_proto', 'rarp' })
   parse_test("ether proto \\100",
              { 'ether_proto', 100 })
   parse_test("ip proto tcp",
              { 'ip_proto', 'tcp' })
   parse_test("ip proto \\tcp",
              { 'ip_proto', 'tcp' })
   parse_test("ip proto \\0",
              { 'ip_proto', 0 })
   parse_test("decnet host 10.23",
              { 'decnet_host', { 'decnet', 10, 23 } })
   parse_test("ip proto icmp",
              { 'ip_proto', 'icmp' })
   parse_test("ip6 protochain icmp",
              { 'ip6_protochain', 'icmp' })
   parse_test("ip6 protochain 100",
              { 'ip6_protochain', 100 })
   parse_test("ip",
              { 'ip' })
   parse_test("type mgt",
              { 'type', 'mgt' })
   parse_test("type mgt subtype deauth",
              { 'type', 'mgt', 'deauth' })
   parse_test("1+1=2",
              { '=', { '+', 1, 1 }, 2 })
   parse_test("len=4", { '=', 'len', 4 })
   parse_test("(len-4>10)", { '>', { '-', 'len', 4 }, 10 })
   parse_test("len == 4", { '=', 'len', 4 })
   parse_test("sctp", { 'sctp' })
   parse_test("1+2*3+4=5",
              { '=', { '+', { '+', 1, { '*', 2, 3 } }, 4 }, 5 })
   parse_test("1+1=2 and tcp",
              { 'and', { '=', { '+', 1, 1 }, 2 }, { 'tcp' } })
   parse_test("tcp port 80 and 1+1=2",
              { 'and', { 'tcp_port', 80 }, { '=', { '+', 1, 1 }, 2 } })
   parse_test("1+1=2 and tcp or tcp",
              { 'or', { 'and', { '=', { '+', 1, 1 }, 2 }, { 'tcp' } }, { 'tcp' } })
   parse_test("1+1=2 or tcp and tcp",
              { 'and', { 'or', { '=', { '+', 1, 1 }, 2 }, { 'tcp' } }, { 'tcp' } })
   parse_test("not 1=1 or tcp",
              { 'or', { 'not', { '=', 1, 1 } }, { 'tcp' } })
   parse_test("not (1=1 or tcp)",
              { 'not', { 'or', { '=', 1, 1 }, { 'tcp' } } })
   parse_test("1+1=2 and (tcp)",
              { 'and', { '=', { '+', 1, 1 }, 2 }, { 'tcp' } })
   parse_test("tcp && ip || !1=1",
              { '||', { '&&', { 'tcp' }, { 'ip' } }, { '!', { '=', 1, 1 } } })
   parse_test("tcp src portrange 80-90",
              { 'tcp_src_portrange', { 80, 90 } })
   parse_test("tcp src portrange ftp-data-90",
              { 'tcp_src_portrange', { 20, 90 } })
   parse_test("tcp src portrange 80-ftp-data",
              { 'tcp_src_portrange', { 20, 80 } }) -- swapped!
   parse_test("tcp src portrange ftp-data-iso-tsap",
              { 'tcp_src_portrange', { 20, 102 } })
   parse_test("tcp src portrange echo-ftp-data",
              { 'tcp_src_portrange', { 7, 20 } })
   parse_test("tcp port 80",
              { 'tcp_port', 80 })
   parse_test("tcp port 0x50",
              { 'tcp_port', 80 })
   parse_test("tcp port 0120",
              { 'tcp_port', 80 })
   parse_test("tcp port 80 and (((ip[2:2] - ((ip[0]&0xf)<<2)) - ((tcp[12]&0xf0)>>2)) != 0)",
              { "and",
                 { "tcp_port", 80 },
                 { "!=",
                    { "-", { "-", { "[ip]", 2, 2 },
                       { "<<", { "&", { "[ip]", 0, 1 }, 15 }, 2 } },
                    { ">>", { "&", { "[tcp]", 12, 1 }, 240 }, 2 } }, 0 } })
   parse_test("ether host ff:ff:ff:33:33:33",
             { 'ether_host', { 'ehost', 255, 255, 255, 51, 51, 51 } })
   parse_test("fddi host ff:ff:ff:33:33:33",
             { 'fddi_host', { 'ehost', 255, 255, 255, 51, 51, 51 } })
   parse_test("tr host ff:ff:ff:33:33:33",
             { 'tr_host', { 'ehost', 255, 255, 255, 51, 51, 51 } })
   parse_test("wlan host ff:ff:ff:33:33:33",
             { 'wlan_host', { 'ehost', 255, 255, 255, 51, 51, 51 } })
   parse_test("ether host f:f:f:3:3:3",
             { 'ether_host', { 'ehost', 15, 15, 15, 3, 3, 3 } })
   parse_test("src net 192.168.1.0/24",
             { 'src_net', { 'ipv4/len', { 'ipv4', 192, 168, 1, 0 }, 24 } })
   parse_test("src net 192.168.1.0 mask 255.255.255.0",
             { 'src_net', { 'ipv4/mask', { 'ipv4', 192, 168, 1, 0 }, { 'ipv4', 255, 255, 255, 0 } } })
   parse_test("host 0:0:0:0:0:0:0:1",
             { 'host', { 'ipv6', 0, 0, 0, 0, 0, 0, 0, 1 } })
   parse_test("host ::1",
             { 'host', { 'ipv6', 0, 0, 0, 0, 0, 0, 0, 1 } })
   parse_test("host 1::1",
             { 'host', { 'ipv6', 1, 0, 0, 0, 0, 0, 0, 1 } })
   parse_test("host 1::",
             { 'host', { 'ipv6', 1, 0, 0, 0, 0, 0, 0, 0 } })
   parse_test("src net eee:eee::0/96",
             { 'src_net', { 'ipv6/len', { 'ipv6', 3822, 3822, 0, 0, 0, 0, 0, 0 }, 96 } })
   parse_test("src net 3ffe:500::/28",
             { 'src_net', { 'ipv6/len', { 'ipv6', 16382, 1280, 0, 0, 0, 0, 0, 0 }, 28 } })
   parse_test("src net 192.168.1.0/24",
             { 'src_net', { 'ipv4/len', { 'ipv4', 192, 168, 1, 0 }, 24 } })
   parse_test("src net 192.168.1.0 mask 255.255.255.0",
             { 'src_net', { 'ipv4/mask', { 'ipv4', 192, 168, 1, 0 }, { 'ipv4', 255, 255, 255, 0 } } })
   parse_test("less 100", {"less", 100})
   parse_test("greater 50 + 50", {"greater", {"+", 50, 50}})
   parse_test("sctp[8] < 8", {'<', { '[sctp]', 8, 1 }, 8})
   parse_test("igmp[8] < 8", {'<', { '[igmp]', 8, 1 }, 8})
   parse_test("igrp[8] < 8", {'<', { '[igrp]', 8, 1 }, 8})
   parse_test("pim[8] < 8", {'<', { '[pim]', 8, 1 }, 8})
   parse_test("vrrp[8] < 8", {'<', { '[vrrp]', 8, 1 }, 8})
   parse_test("not icmp6", {'not', { 'icmp6' } })
   parse_test("icmp[icmptype] != icmp-echo and icmp[icmptype] != icmp-echoreply",
              { "and",
                { "!=", { "[icmp]", 0, 1 }, 8 },
                { "!=", { "[icmp]", 0, 1 }, 0 } })
   parse_test("net 192.0.0.0", {'net', { 'ipv4', 192, 0, 0, 0 } })
   parse_test("net 192.168.1.0/24",
               { 'net', { 'ipv4/len', { 'ipv4', 192, 168, 1, 0 }, 24 } })
   parse_test("net 192.168.1",
               { 'net', { 'ipv4/len', { 'ipv4', 192, 168, 1, 0 }, 24 } })
   parse_test("net 192.168",
               { 'net', { 'ipv4/len', { 'ipv4', 192, 168, 0, 0 }, 16 } })
   parse_test("net 192",
               { 'net', { 'ipv4/len', { 'ipv4', 192, 0, 0, 0 }, 8 } })
   parse_test("net  192",
               { 'net', { 'ipv4/len', { 'ipv4', 192, 0, 0, 0 }, 8 } })

   local function parse_error_test(str, expected_err)
      local ok, actual_err = pcall(parse, str)
      assert(not ok, "expected error, got no error")
      if expected_err then
         assert(actual_err:find(expected_err, 1, true),
                "expected error "..expected_err.." but got "..actual_err)
      end
   end
   parse_error_test("tcp src portrange 80-fffftp-data", "error parsing portrange 80-fffftp-data")
   parse_error_test("tcp src portrange 80000-90000", "port 80000 out of range")
   parse_error_test("tcp src portrange 0x1-0x2", "error parsing portrange 0x1-0x2")
   parse_error_test("tcp src portrange ::1", "error parsing portrange :")
   parse_error_test("tcp src port ::1", "unsupported port :")
   parse_error_test("123$", "unexpected end of decimal literal at 1")
   parse_error_test("0x123$", "unexpected end of hexadecimal literal at 1")
   parse_error_test("0123$", "unexpected end of octal literal at 1")
   parse_error_test("0 = 0x", "unexpected end of hexadecimal literal at 5")
   parse_error_test("0 = 08", "unexpected end of octal literal at 5")
   parse_error_test("0 = 09", "unexpected end of octal literal at 5")
   parse_error_test("host 0xffffffffff and tcp", "integer too large: 0xffffffffff")
   parse_error_test("host ff:ff:ff:ff:ff:ff", "ethernet address used in non-ether expression")
   parse_error_test("net ff:ff:ff:ff:ff:ff", "ethernet address used in non-ether expression")
   parse_error_test("net 192.168.1.0 mask foobar", "Invalid IPv4 mask")
   parse_error_test("net 192.168.1.0 mask ::", "Invalid IPv4 mask")
   parse_error_test("net 192.168.1.0 mask ff:ff:ff:ff:ff:ff", "Invalid IPv4 mask")
   print("OK")
end
