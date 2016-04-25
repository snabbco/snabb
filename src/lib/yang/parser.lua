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
   elseif chr == "\t" then
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

function Parser:skip_c_comment()
   repeat
      self:take_while("[^*]")
      self:consume("*")
   until self:check("/")
end

-- Returns true if has consumed any whitespace
function Parser:skip_whitespace()
   local result = false
   if self:take_while('%s') ~= "" then result = true end
   -- Skip comments, which start with # and continue to the end of line.
   while self:check('/') do
      result = true
      if self:check("*") then self:skip_c_comment()
      else
	 self:consume("/")
	 self:take_while('[^\n]')
	 self:take_while('%s')
      end
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
	    result = result..string.rep(" ", self.column-start_column)
	 end
      elseif self:check("\\") then
	 if self:check("n") then result = result.."\n"
	 elseif self:check("t") then result = result.."\t"
	 elseif self:check('"') then result = result..'"'
	 elseif self:check("\\") then result = result.."\\"
	 else
	    result = result.."\\"
	 end

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

function Parser:parse_string()
   if self:check("'") then return self:parse_qstring("'")
   elseif self:check('"') then return self:parse_qstring('"')
   else return self:take_while("[^%s;{}\"'/]") end
end

function Parser:parse_identifier()
   local id = self:parse_string()
   if not id == "" then self:error("Expected identifier") end
   if not id:match("^[%a_][%w_.-]*$") then self:error("Invalid identifier") end
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

function Parser:parse_module()
   local statements = self:parse_statement_list()
   if not self:is_eof() then error("Not end of file") end
   return statements
end

function Parser:parse_statement_list()
   local statements = {}

   while true do
      self:skip_whitespace()
      if self:is_eof() or self:peek() == "}" then
	 break
      end

      table.insert(statements, self:parse_statement())
   end

   return statements

end

function Parser:parse_statement()
   self:skip_whitespace()

   local returnval = {}

   -- Then must be a string that is the leaf's identifier
   local keyword = self:parse_keyword()
   if keyword == "" then
      self:error("keyword expected")
   end
   returnval.keyword = keyword
   self:consume_whitespace()

   -- Take the identifier
   local argument = self:parse_string()
   if argument ~= "" then returnval.argument = argument end
   self:skip_whitespace()

   if self:check(";") then
      return returnval
   end

   if self:check("{") then
      returnval.statements = self:parse_statement_list()
      self:consume("}")
      return returnval
   end

   self:error("Unexpected character found")
end

function selftest()
   local function assert_equal(a, b)
      if not lib.equal(a, b) then
         print(a, b)
         error("not equal")
      end
   end

   local function test_string(src, exp)
      local parser = Parser.new(src)
      parser:skip_whitespace()

      assert_equal(parser:parse_string(), exp)
   end

   local function pp(x)
      if type(x) == "table" then
	 io.write("{")
	 local first = true
	 for k,v in pairs(x) do
	    if not first then
	       io.write(", ")
	    end
	    io.write(k.."=")
	    pp(v)
	    first = false
	 end
	 io.write("}")
      elseif type(x) == "string" then
	 io.write(x)
      else
	 error("Unsupported type")
      end
   end


   local function test_module(src, exp)
      local parser = Parser.new(src)
      local result = parser:parse_module()
      if not lib.equal(result, exp) then
	 pp(result)
	 pp(exp)
	 error("no equal")
      end
   end

   local function lines(...)
      return table.concat({...}, "\n")
   end

   -- Test the string parser
   test_string("foo", "foo")
   test_string([["foo"]], "foo")
   test_string([["foo"+"bar"]], "foobar")
   test_string([['foo'+"bar"]], "foobar")
   test_string("'foo\\nbar'", "foo\\nbar")
   test_string('"foo\\nbar"', "foo\nbar")
   test_string('"// foo bar;"', '// foo bar;')
   test_string('"/* foo bar */"', '/* foo bar */')
   test_string([["foo \"bar\""]], 'foo "bar"')
   test_string(lines("  'foo",
		     "    bar'"),
	       lines("foo", " bar"))
   test_string(lines("  'foo",
		     "  bar'"),
	       lines("foo", "bar"))
   test_string(lines("   'foo",
		     "\tbar'"),
	       lines("foo", "    bar"))
   test_string(lines("   'foo",
		     " bar'"),
	       lines("foo", "bar"))


   test_module("type string;", {{keyword="type", argument="string"}})
   test_module("/** **/", {})
   test_module("// foo bar;", {})
   test_module("// foo bar;\nleaf port;", {{keyword="leaf", argument="port"}})
   test_module("type/** hellooo */string;", {{keyword="type", argument="string"}})
   test_module('type "hello\\pq";', {{keyword="type", argument="hello\\pq"}})


   local fin = assert(io.open("example.yang"))
   local yangexample = fin:read("*a")
   local parser = Parser.new(yangexample, "example.yang")
   parser:parse_module()
end
