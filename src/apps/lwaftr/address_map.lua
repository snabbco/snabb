module(..., package.seeall)
-- 
--                      0                   1
--                      0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5
--                     +-----------+-----------+-------+
--       Ports in      |     A     |    PSID   |   j   |
--    the CE port set  |    > 0    |           |       |
--                     +-----------+-----------+-------+
--                     |  a bits   |  k bits   |m bits |
-- 
--             Figure 2: Structure of a Port-Restricted Port Field
-- 
--   a bits = reserved_ports_bit_count.
--   k bits = psid_length.
--   m bits = shift.
-- 
-- Source: http://tools.ietf.org/html/rfc7597#section-5.1 

local ffi = require("ffi")
local rangemap = require("apps.lwaftr.rangemap")

local address_map_value = ffi.typeof([[
   struct { uint16_t psid_length; uint16_t shift; }
]])

local function read_char(f)
   local chr = f.next()
   if chr then
      if chr == '\n' then
         f.column = 0
         f.line = f.line + 1
      else
         f.column = f.column + 1
      end
   end
   return chr
end

local function parse_error(f, message)
   error(f.name..':'..f.line..':'..f.column..': error: '..message)
end

local function consume_char(f, chr, expected)
   if chr == nil then parse_error(f, 'expected '..expected..', got EOF') end
   if chr ~= expected then
      parse_error(f, 'expected '..expected..' instead of '..chr)
   end
end

local function take_while(f, chr, pattern)
   if not chr then chr = read_char(f) end
   local res = {}
   while chr and chr:match(pattern) do
      table.insert(res, chr)
      chr = read_char(f)
   end
   return table.concat(res), chr
end

local function skip_whitespace(f, chr)
   local _, chr = take_while(f, chr, '%s')
   return chr
end

local function parse_uint(f, chr, min, max)
   local tok, chr = take_while(f, chr, '%d')
   if tok == '' then parse_error(f, 'expected a number') end
   if #tok > #(tostring(max)) then
      parse_error('numeric constant too long: '..tok)
   end
   local uint = tonumber(tok)
   if uint < min or uint > max then
      parse_error('numeric constant out of range: '..uint)
   end
   return uint, chr
end

local function parse_psid_param(f, chr)
   return parse_uint(f, chr, 0, 16)
end

local function parse_ipv4_quad(f, chr)
   return parse_uint(f, chr, 0, 255)
end

local function read_kvlist(f, chr, spec)
   chr = skip_whitespace(f, chr)
   consume_char(f, chr, '{')
   local res = {}
   chr = skip_whitespace(f)
   local tok
   while chr and chr ~= '}' do
      tok, chr = take_while(f, chr, '[%w_]')
      local key = tok
      if key == '' then break end
      if res[key] then parse_error(f, 'duplicate key: '..key) end
      if not spec.parse[key] then parse_error(f, 'unexpected key: '..key) end
      chr = skip_whitespace(f, chr)
      consume_char(f, chr, '=')
      chr = skip_whitespace(f)
      tok, chr = spec.parse[key](f, chr)
      res[key] = tok
      local line = f.line
      if chr == '\n' then line = line - 1 end
      chr = skip_whitespace(f, chr)
      if chr == ',' then
         chr = skip_whitespace(f)
      elseif chr ~= '}' and f.line == line then
         parse_error(f, 'expected comma, new line, or }')
      end
   end
   consume_char(f, chr, '}')
   for k, default in pairs(spec.defaults) do
      if not res[k] then res[k] = default(res) end
   end
   spec.validate(f, res)
   return res
end

local psid_info_spec = {
   parse={
      psid_length=parse_psid_param,
      shift=parse_psid_param
   },
   defaults={
      psid_length=function (config) return 16 - (config.shift or 16) end,
      shift=function(config) return 16 - (config.psid_length or 0) end
   },
   validate=function(f, config)
      if config.psid_length + config.shift ~= 16 then
         parse_error(f, 'psid_length '..config.psid_length..' + shift '..config.shift..' should add to 16')
      end
   end
}

local function read_psid_info(f, chr)
   return read_kvlist(f, chr, psid_info_spec)
end

local function read_ipv4(f, chr)
   local q1, chr = parse_ipv4_quad(f, chr)
   consume_char(f, chr, '.')
   local q2, chr = parse_ipv4_quad(f)
   consume_char(f, chr, '.')
   local q3, chr = parse_ipv4_quad(f)
   consume_char(f, chr, '.')
   local q4, chr = parse_ipv4_quad(f)
   return { q1, q2, q3, q4 }, chr
end

local function read_entry(f, chr)
   local ipv4, chr = read_ipv4(f, chr)
   local info, chr = read_psid_info(f, chr)
   info.host_endian_ipv4 = ipv4[1]*2^24 + ipv4[2]*2^16 + ipv4[3]*2^8 + ipv4[4]
   return info, chr
end

local function read_entries(f)
   local entries = {}
   local chr = skip_whitespace(f)
   while chr do
      local info
      info, chr = read_entry(f, chr)
      table.insert(entries, info)
      chr = skip_whitespace(f, chr)
   end
   return entries
end

local function parse(file)
   local stream = {}
   if type(file) == 'string' then
      f = io.open(file)
      function stream.next() return f:read(1) end
      stream.name = file
   else
      function stream.next() return file:read(1) end
      stream.name = '<unknown>'
   end
   stream.column = 0
   stream.line = 1
   return read_entries(stream)
end

local function attach_lookup_helper(map)
   local function port_to_psid(port, psid_len, shift)
      local psid_mask = lshift(1, psid_len)-1
      local psid = band(rshift(port, shift), psid_mask)
      -- There are restricted ports.
      if psid_len + shift < 16 then
         local reserved_ports_bit_count = 16 - psid_len - shift
         local first_allocated_port = lshift(1, reserved_ports_bit_count)
         -- Port is within the range of restricted ports, assign bogus
         -- PSID so lookup will fail.
         if port < first_allocated_port then psid = psid_mask + 1 end
      end
      return psid
   end

   function map:lookup_psid(ipv4, port)
      local psid_info = self:lookup(ipv4).value
      local psid_len, shift = psid_info.psid_len, psid_info.shift
      return port_to_psid(port, psid_len, shift)
   end
   return map
end

function compile(file)
   local builder = rangemap.RangeMapBuilder.new(address_map_value)
   local value = address_map_value()
   for _, entry in ipairs(parse(file)) do
      value.psid_length = entry.psid_length
      value.shift = entry.shift
      builder:add(entry.host_endian_ipv4, value)
   end
   return attach_lookup_helper(builder:build())
end

function selftest()
   print('selftest: address_map')
   local assert_equals = require('pf.utils').assert_equals
   local function string_file(str)
      local pos = 1
      return {
         read = function(self, n)
            assert(n==1)
            local ret
            if pos <= #str then
               ret = str:sub(pos,pos)
               pos = pos + 1
            end
            return ret
         end
      }
   end
   local function parse_string(str) return parse(string_file(str)) end
   local function test(str, expected)
      assert_equals(parse_string(str), expected)
      if str ~= '' then compile(string_file(str)) end
   end
   test('', {})
   test('1.0.0.0{}',
        {{host_endian_ipv4=2^24, psid_length=0, shift=16}})
   test('1.0.0.0 {psid_length=10}',
        {{host_endian_ipv4=2^24, psid_length=10, shift=6}})
   test('1.0.0.0 {shift=6}',
        {{host_endian_ipv4=2^24, psid_length=10, shift=6}})
   test('1.0.0.0 {shift=7,psid_length=9}',
        {{host_endian_ipv4=2^24, psid_length=9, shift=7}})
   test('1.0.0.0 {psid_length=7,shift=9}',
        {{host_endian_ipv4=2^24, psid_length=7, shift=9}})
   test([[
            1.0.0.0 {psid_length=7,shift=9}
            2.0.0.0 {}
        ]],
        {{host_endian_ipv4=2^24, psid_length=7, shift=9},
         {host_endian_ipv4=2^25, psid_length=0, shift=16}})
   print('ok')
end
