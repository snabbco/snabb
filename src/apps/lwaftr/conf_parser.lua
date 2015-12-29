module(..., package.seeall)

local ffi = require("ffi")
local S = require("syscall")

Parser = {}

function Parser.new(file)
   local name = '<unknown>'
   local mtime_sec, mtime_nsec
   if type(file) == 'string' then
      name, file = file, io.open(file)
      -- Seems to be no way to fstat() the file.  Oh well.
      local stat = S.stat(name)
      mtime_sec, mtime_nsec = stat.st_mtime, stat.st_mtime_nsec
      print(mtime_sec, mtime_nsec)
   end
   local ret = {
      column=0, line=0, name=name, mtime_sec=mtime_sec, mtime_nsec=mtime_nsec
   }
   function ret.read_char() return file:read(1) end
   function ret.cleanup() return file:close() end
   ret.peek_char = ret.read_char()
   return setmetatable(ret, {__index=Parser})
end

function Parser:error(msg, ...)
   self.cleanup()
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
      if expected == nil then return true end
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
      if not spec.parse[key] then self:error('unexpected key: %s', key) end
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
      if not res[k] then res[k] = default(res) end
   end
   spec.validate(self, res)
   return res
end

-- Parse IPv4 address as host-endian integer.
function Parser:parse_ipv4()
   local q1 = self:parse_ipv4_quad()
   self:consume('.')
   local q2 = self:parse_ipv4_quad()
   self:consume('.')
   local q3 = self:parse_ipv4_quad()
   self:consume('.')
   local q4 = self:parse_ipv4_quad()
   return q1*2^24 + q2*2^16 + q3*2^8 + q4
end

function Parser:parse_ipv4_range()
   local range_begin, range_end
   range_begin = self:parse_ipv4()
   self:skip_whitespace()
   if self:check('-') then
      self:skip_whitespace()
      range_end = self:parse_ipv4()
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
