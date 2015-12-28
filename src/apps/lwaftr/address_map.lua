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

Parser = {}

function Parser.new(file)
   local name = '<unknown>'
   if type(file) == 'string' then name, file = file, io.open(file) end
   local ret = { column=0, line=0, name=name }
   function ret.read_char() return file:read(1) end
   ret.peek_char = ret.read_char()
   return setmetatable(ret, {__index=Parser})
end

function Parser:error(msg, ...)
   error(('%s:%d:%d: error: '..msg):format(self.name, self.line, self.column,
                                           ...))
end

function Parser:next()
   local chr = self.peek_char
   if chr == '\n' then
      self.column = 0
      self.line = self.line + 1
   elseif chr then
      self.column = self.column + 1
   end
   self.peek_char = self.read_char()
   return chr
end

function Parser:peek() return self.peek_char end
function Parser:is_eof() return not self:peek() end

function Parser:check(expected)
   if self:is_eof() then
      self:error("while looking for '%s', got EOF", expected)
   elseif self:peek() == expected then
      self:next()
      return true
   end
   return false
end

function Parser:consume(expected)
   if not self:check(expected) then
      self:error("expected '%s', got '%s'", expected, self:peek())
   end
end

function Parser:take_while(pattern)
   local res = {}
   while not self:is_eof() and self:peek():match(pattern) do
      table.insert(res, self:next())
   end
   return table.concat(res)
end

function Parser:skip_whitespace() self:take_while('%s') end

function Parser:parse_uint(min, max)
   local tok = self:take_while('%d')
   if tok == '' then self:error('expected a number') end
   if #tok > #(tostring(max)) then
      self:error('numeric constant too long: %s', tok)
   end
   local uint = tonumber(tok)
   if uint < min or uint > max then
      self:error('numeric constant out of range: %d', uint)
   end
   return uint
end

function Parser:parse_psid_param() return self:parse_uint(0, 16) end
function Parser:parse_ipv4_quad() return self:parse_uint(0, 255) end

function Parser:parse_kvlist(spec)
   local res = {}
   self:skip_whitespace()
   self:consume('{')
   self:skip_whitespace()
   while not self:check('}') do
      local key = self:take_while('[%w_]')
      if key == '' then
         self:error("expected a key=value property or a closing '}'")
      end
      if res[key] then self:error('duplicate key: %s', key) end
      if not spec.parse[key] then self:error('unexpected key: %s', key) end
      self:skip_whitespace()
      self:consume('=')
      self:skip_whitespace()
      local val = spec.parse[key](self)
      res[key] = val

      -- Key-value pairs are separated by newlines or commas, and
      -- terminated by }.  A trailing comma is optional.
      local line = self.line
      self:skip_whitespace()
      local has_comma = self:check(',')
      if has_comma then self:skip_whitespace() end
      if self:check('}') then break end
      if not has_comma and self.line == line then
         self:error('properties should be separated by commas or newlines')
      end
   end
   for k, default in pairs(spec.defaults) do
      if not res[k] then res[k] = default(res) end
   end
   spec.validate(self, res)
   return res
end

local psid_info_spec = {
   parse={
      psid_length=Parser.parse_psid_param,
      shift=Parser.parse_psid_param
   },
   defaults={
      psid_length=function(config) return 16 - (config.shift or 16) end,
      shift=function(config) return 16 - (config.psid_length or 0) end
   },
   validate=function(self, config)
      if config.psid_length + config.shift ~= 16 then
         self:error('psid_length %d + shift %d should add up to 16',
                    config.psid_length, config.shift)
      end
   end
}

function Parser:parse_psid_info()
   return self:parse_kvlist(psid_info_spec)
end

function Parser:parse_ipv4()
   local q1 = self:parse_ipv4_quad()
   self:consume('.')
   local q2 = self:parse_ipv4_quad()
   self:consume('.')
   local q3 = self:parse_ipv4_quad()
   self:consume('.')
   local q4 = self:parse_ipv4_quad()
   return { q1, q2, q3, q4 }
end

function Parser:parse_entry()
   local ipv4 = self:parse_ipv4()
   local info = self:parse_psid_info()
   info.host_endian_ipv4 = ipv4[1]*2^24 + ipv4[2]*2^16 + ipv4[3]*2^8 + ipv4[4]
   return info
end

function Parser:parse_entries()
   local entries = {}
   self:skip_whitespace()
   while not self:is_eof() do
      table.insert(entries, self:parse_entry())
      self:skip_whitespace()
   end
   return entries
end

local function parse(stream)
   return Parser.new(stream):parse_entries()
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
