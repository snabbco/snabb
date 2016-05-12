module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local ethernet = require("lib.protocol.ethernet")

Parser = {}

function Parser.new(file)
   local name = file.name
   if type(file) == 'string' then
      name, file = file, io.open(file)
   end
   local ret = { column=0, line=1, name=name }
   function ret.read_char() return file:read(1) end
   function ret.cleanup()
      function ret.cleanup() end
      return file:close()
   end
   ret.peek_char = ret.read_char()
   return setmetatable(ret, {__index=Parser})
end

function Parser:error(msg, ...)
   self.cleanup()
   error(('%s:%d:%d: error: '..msg):format(
         self.name or '<unknown>', self.line, self.column, ...))
end

function Parser:next()
   local chr = self.peek_char
   if chr == '\n' then
      self.column = 0
      self.line = self.line + 1
   elseif chr then
      self.column = self.column + 1
   else
      self.cleanup()
   end
   self.peek_char = self.read_char()
   return chr
end

function Parser:peek() return self.peek_char end
function Parser:is_eof() return not self:peek() end

function Parser:check(expected)
   if self:peek() == expected then
      if expected then self:next() end
      return true
   end
   return false
end

function Parser:consume(expected)
   if not self:check(expected) then
      local ch = self:peek()
      if ch == nil then
         self:error("while looking for '%s', got EOF", expected)
      elseif expected then
         self:error("expected '%s', got '%s'", expected, ch)
      else
         self:error("expected EOF, got '%s'", ch)
      end
   end
end

function Parser:take_while(pattern)
   local res = {}
   while not self:is_eof() and self:peek():match(pattern) do
      table.insert(res, self:next())
   end
   return table.concat(res)
end

function Parser:consume_token(pattern, expected)
   local tok = self:take_while(pattern)
   if tok:lower() ~= expected then
      self:error("expected '%s', got '%s'", expected, tok)
   end
end

function Parser:skip_whitespace()
   self:take_while('%s')
   -- Skip comments, which start with # and continue to the end of line.
   while self:check('#') do
      self:take_while('[^\n]')
      self:take_while('%s')
   end
end

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

function Parser:parse_property_list(spec, bra, ket)
   local res = {}
   self:skip_whitespace()
   if bra then
      self:consume(bra)
      self:skip_whitespace()
   end
   while not self:check(ket) do
      local key = self:take_while('[%w_]')
      if key == '' then
         self:error("expected a key=value property or a closing '%s'", ket)
      end
      if res[key] then self:error('duplicate key: %s', key) end
      if not spec.parse[key] then self:error('unexpected key: "%s"', key) end
      self:skip_whitespace()
      self:consume('=')
      self:skip_whitespace()
      local val = spec.parse[key](self)
      res[key] = val

      -- Key-value pairs are separated by newlines or commas, and
      -- terminated by the ket.  A trailing comma is optional.
      local line = self.line
      self:skip_whitespace()
      local has_comma = self:check(',')
      if has_comma then self:skip_whitespace() end
      if self:check(ket) then break end
      if not has_comma and self.line == line then
         self:error('properties should be separated by commas or newlines')
      end
   end
   for k, default in pairs(spec.defaults) do
      if res[k] == nil then res[k] = default(res) end
   end
   spec.validate(self, res)
   return res
end

-- Returns a uint8_t[4].
function Parser:parse_ipv4()
   local addr_string = self:take_while('[%d.]')
   if not addr_string or #addr_string == 0 then
      self:error("IPv4 address expected")
   end
   local addr, err = ipv4:pton(addr_string)
   if not addr then self:error('%s', err) end
   return addr
end

function Parser:parse_ipv4_as_uint32()
   local addr = self:parse_ipv4()
   return ffi.C.htonl(ffi.cast('uint32_t*', addr)[0])
end

-- Returns a uint8_t[16].
function Parser:parse_ipv6()
   local addr_string = self:take_while('[%x:]')
   if not addr_string or #addr_string == 0 then
      self:error("IPv6 address expected")
   end
   local addr, err = ipv6:pton(addr_string)
   if not addr then self:error('%s', err) end
   return addr
end

-- Returns a uint8_t[6].
function Parser:parse_mac()
   local addr_string = self:take_while('[%x:]')
   if not addr_string or #addr_string == 0 then
      self:error("Ethernet MAC address expected")
   end
   -- FIXME: Unlike ipv6:pton, ethernet:pton raises an error if the
   -- address is invalid.
   local success, addr_or_err = pcall(ethernet.pton, ethernet, addr_string)
   if not success then self:error('%s', addr_or_err) end
   return addr_or_err
end

function Parser:parse_ipv4_range()
   local range_begin, range_end
   range_begin = self:parse_ipv4_as_uint32()
   self:skip_whitespace()
   if self:check('-') then
      self:skip_whitespace()
      range_end = self:parse_ipv4_as_uint32()
   else
      range_end = range_begin
   end
   if range_end < range_begin then
      self:error('invalid IPv4 address range (end before begin)')
   end
   return { min=range_begin, max=range_end }
end

function Parser:parse_ipv4_range_list()
   local ranges = {}
   repeat
      self:skip_whitespace()
      table.insert(ranges, self:parse_ipv4_range())
      self:skip_whitespace()
   until not self:check(',')
   return ranges
end

function Parser:parse_quoted_string(quote, escape)
   local res = {}
   escape = escape or '\\'
   while not self:check(quote) do
      local ch = self:next()
      if ch == escape then ch = self:next() end
      if not ch then self:error('EOF while reading quoted string') end
      table.insert(res, ch)
   end
   return table.concat(res)
end

function Parser:parse_string()
   local str
   if self:check("'") then str = self:parse_quoted_string("'")
   elseif self:check('"') then str = self:parse_quoted_string('"')
   else str = self:take_while('[^%s,]') end
   return str
end

function Parser:make_path(orig_path)
   if orig_path == '' then self:error('file name is empty') end
   if not orig_path:match('^/') and self.name then
      -- Relative paths in conf files are relative to the location of the
      -- conf file, not the current working directory.
      return lib.dirname(self.name)..'/'..orig_path
   end
   return orig_path
end

function Parser:parse_file_name()
   return self:make_path(self:parse_string())
end

function Parser:parse_string_or_file()
   local str = self:parse_string()
   if not str:match('^<') then
      return str
   end
   -- Remove the angle bracket.
   path = self:make_path(str:sub(2))
   local filter, err = lib.readfile(path, "*a")
   if filter == nil then
      self:error('cannot read filter conf file "%s": %s', path, err)
   end
   return filter
end

function Parser:parse_boolean()
   local tok = self:take_while('[%a]')
   if tok:lower() == 'true' then return true end
   if tok:lower() == 'false' then return false end
   self:error('expected "true" or "false", instead got "%s"', tok)
end

function Parser:parse_number()
   local tok = self:take_while('[%d.eExX]')
   local num = tonumber(tok)
   if not num then self:error('expected a number, instead got "%s"', tok) end
   return num
end

function Parser:parse_positive_number()
   local num = self:parse_number()
   if num <= 0 then
      self:error('expected a positive number, instead got %s',
                 tostring(num))
   end
   return num
end

function Parser:parse_non_negative_number()
   local num = self:parse_number()
   if num < 0 then
      self:error('expected a non-negative number, instead got %s',
                 tostring(num))
   end
   return num
end

function Parser:parse_mtu()
   return self:parse_uint(0,2^16-1)
end

function Parser:parse_psid()
   return self:parse_uint(0,2^16-1)
end

function Parser.enum_parser(enums)
   return function(self)
      local tok = self:parse_string()
      for k,v in pairs(enums) do
         if k:lower() == tok:lower() then return v end
      end
      -- Not found; make a nice error.
      local keys = {}
      for k,_ in pairs(enums) do table.insert(keys, k) end
      keys = table.concat(keys, ', ')
      self:error('bad value: "%s".  expected one of %s', tok, keys)
   end
end

function Parser:parse_vlan_tag()
   return self:parse_uint(0,2^12-1)
end
