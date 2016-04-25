module(..., package.seeall)

local lib = require('core.lib')

local function new_type()
   local Type = {}
   Type.__index = Type
   return Type
end

local Leaf = new_type()
function Leaf.new(properties)
   return setmetatable(properties, Leaf)
end

local Parser = new_type()
function Parser.new(str, filename)
   local ret = { pos=1, str=str, filename=filename, line=1, column=0, line_pos=1}
   ret = setmetatable(ret, Parser)
   ret.peek_char = ret:read_char()
   return ret
end

function Parser:error(msg, ...)
   print(self.str:match("[^\n]*", self.line_pos))
   print(string.rep(" ", self.column).."^")
   error(('%s:%d:%d: error: '..msg):format(
         self.name or '<unknown>', self.line, self.column, ...))
end

function Parser:read_char()
   if self.pos <= #self.str then
      local ret = self.str:sub(self.pos,self.pos)
      self.pos = self.pos + 1
      return ret
   end
end

function Parser:peek() return self.peek_char end
function Parser:is_eof() return not self:peek() end

function Parser:next()
   local chr = self.peek_char
   if chr == '\n' then
      self.line_pos = self.pos + 1
      self.column = 0
      self.line = self.line + 1
   elseif char == "\t" then
      self.column = self.column + 8
      self.column = 8 * math.floor(self.column / 8)
   elseif chr then
      self.column = self.column + 1
   end
   self.peek_char = self:read_char()
   return chr
end

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

-- Returns true if has consumed any whitespace
function Parser:skip_whitespace()
   local result = false
   if self:take_while('%s') ~= "" then result = true end
   -- Skip comments, which start with # and continue to the end of line.
   while self:check('#') do
      result = true
      self:take_while('[^\n]')
      self:take_while('%s')
   end
   return result
end

function Parser:consume_whitespace()
   if not self:skip_whitespace() then
      self:error("Missing whitespace")
   end
end

function Parser:consume_token(pattern, expected)
   local tok = self:take_while(pattern)
   if tok:lower() ~= expected then
      self:error("expected '%s', got '%s'", expected, tok)
   end
end

function Parser:parse_qstring(quote)
   local start_column = self.column
   self:check(quote)
   local terminators = "\n"..quote
   if quote == '"' then terminators = terminators.."\\" end

   local result = ""
   while true do
      result = result..self:take_while("[^"..terminators.."]")
      if self:check(quote) then break end
      if self:check("\n") then
	 while self.column < start_column do
	    if not self:check(" ") and not self:check("\t") then break end
	 end
	 result = result.."\n"
	 if self.column > start_column then
	    result = result..stirng.rep(" ", self.column-start_column)
	 end
      elseif self:check("\\") then
	 if self:check("n") then result = result.."\n"
	 elseif self:check("t") then result = result.."\t"
	 elseif self:check('"') then result = result..'"'
	 elseif self:check("\\") then result = result.."\\"
	 else self:error("Invalid escaped character") end
      end
   end
   self:check(quote)
   self:skip_whitespace()

   if not self:check("+") then return result end
   self:skip_whitespace()

   -- Strings can be concaternated together with a +
   if self:check("'") then
      return result..self:parse_qstring("'")
   elseif self:check('"') then
      return result..self:parse_qstring('"')
   else
      self:error("Expected quote character")
   end
end

function Parser:parse_identifier()
   local id
   if self:check("'") then id = self:parse_qstirng("'")
   elseif self:check('"') then id = self:parse_qstring('"')
   else id = self:take_while("[%w_.-]") end

   if not id == "" then self:error("Expected identifier") end
   if not id:match("^[%a_]") then self:error("Invalid identifier") end

   return id
end

function Parser:parse_keyword()
   self:skip_whitespace()

   if self:is_eof() then
      self:error("Expected keyword")
   end

   local char = self:peek()
   local is_prefix = char == "'" or char == '"'
   local id = self:parse_identifier()

   if self:check(":") then
      local extension_id = self:parse_identifier()
      return {id, extension_id}
   end

   if is_prefix then error("Expected colon") end

   return id
end

function Parser:parse_statement()
   self:consume_whitespace()

   -- Then must be a string that is the leaf's identifier
   local leaf_identifier = self:take_while("%a")
   if leaf_identifier == "" then
      self:error("Leaf identifier expected")
   end
   self:skip_whitespace()

   -- Consume the opening curly brace.
   self:consume("{")
   self:skip_whitespace()

   -- Next we have the property name, some whitespace then the value.
   local properties = {}
   while not self:expect("}") do
      -- Read in the property name
      local property = self:take_while("%a+")
      self:consume_whitespace()

      -- Take the value
      local value = self:take_while("[%w:]")

      -- Check there is a new line (can they also be seperated by commas?)
      local line = self.line
      self:skip_whitespace()
      if self.line == line then
	 self:error("properties should be split by a new line")
      end
   end

   return Leaf.new(properties)
end

function selftest()
   local function assert_equal(a, b)
      if not lib.equal(a, b) then
         print(a, b)
         error("not equal")
      end
   end

   assert(getmetatable(Leaf.new({})) == Leaf)

   local parser = Parser.new("foo", "bar")
   assert_equal(parser:next(), "f")
   assert(parser:next() == "o")
   assert(parser:next() == "o")
   assert(parser:is_eof())
   assert(not parser:next())

   -- Test tsyes' code
   local parser = Parser.new([[
       leaf foo {
           type string;
       }
   ]], "bar")
   -- for now lets just consume the leaf keyword here.
   parser:skip_whitespace()
   parser:consume_token("%a", "leaf")
   local leaf = parser:parse_leaf()

   assert(leaf.type == "string")

end
