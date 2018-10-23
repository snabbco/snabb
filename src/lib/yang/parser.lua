-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- This module implements a YANG parser which will parse a YANG module to a
-- Lua table. This is used by instantiating the Parser with the module and
-- optionally the filename. You then should call Parser:parse_module
--
-- The parser uses the same termanology as the specification (rfc6020). The
-- following is an example YANG module and lua representation:
-- YANG:
--
-- leaf port {
--     type inet:port-number;
--     default;
--     description "The port to which the SSH server listens"
--  }
--
-- Lua table:
-- {
--     {argument="port", keyword="leaf", statements={
--         {keyword="type", argument="inet:port-number"},
--         {keyword="default"},
--         {
--             keyword="description",
--             argument="The port to which the SSH server listens"
--         }}
--     }
-- }

module(..., package.seeall)

local lib = require('core.lib')
local mem = require('lib.stream.mem')

Parser = {}
function Parser.new(stream)
   local ret = {pos=0, str='', stream=stream, line=1, column=0, name=stream:filename()}
   ret = setmetatable(ret, {__index = Parser})
   ret.peek_char = ret:read_char()
   return ret
end

function Parser:loc()
   return string.format('%s:%d:%d', self.name or '<unknown>', self.line,
                        self.column)
end

function Parser:error(msg, ...)
   print(self.str:match("[^\n]*"))
   print(string.rep(" ", self.column).."^")
   print(('%s: error: '..msg):format(self:loc(), ...))
   -- use an empty error to avoid printing stack trace
   error()
end

function Parser:read_char()
   if self.pos == #self.str then
      local str = self.stream:read_line('keep')
      if str == nil then return nil end -- EOF.
      self.str, self.pos = str, 0
   end
   assert(self.pos < #self.str)
   self.pos = self.pos + 1
   return self.str:sub(self.pos,self.pos)
end

function Parser:peek() return self.peek_char end
function Parser:is_eof() return not self:peek() end

function Parser:next()
   local chr = self.peek_char
   if chr == '\n' then
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

-- Only peeks on same line.
function Parser:peek_n(n)
   return self.str:sub(self.pos, math.min(self.pos + n - 1, #self.str))
end

function Parser:check(expected)
   if self:peek() == expected then
      if expected then self:next() end
      return true
   end
   return false
end

function Parser:check_pattern(pattern)
   if not self:is_eof() then
      return self:peek():match(pattern)
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
      if self:check("*") then
         self:skip_c_comment()
      else
         self:consume("/")
         self:take_while('[^\n]')
      end
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
   local terminators = "\n"..quote
   if quote == '"' then terminators = terminators.."\\" end

   local result = {}
   while true do
      table.insert(result, self:take_while("[^"..terminators.."]"))
      if self:check(quote) then break end
      if self:check("\n") then
         while self.column < start_column do
            if not self:check(" ") and not self:check("\t") then break end
         end
         table.insert(result, "\n")
         if self.column > start_column then
            table.insert(result, string.rep(" ", self.column-start_column))
         end
      elseif self:check("\\") then
         if self:check("n")      then table.insert(result, "\n")
         elseif self:check("t")  then table.insert(result, "\t")
         elseif self:check('"')  then table.insert(result, '"')
         elseif self:check("\\") then table.insert(result, "\\")
         else                         table.insert(result, "\\") end
      end
   end
   result = table.concat(result)
   self:check(quote)
   self:skip_whitespace()

   if not self:check("+") then return result end
   self:skip_whitespace()

   -- Strings can be concatenated together with a +
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
   else
      local ret = {}
      repeat
         table.insert(ret, self:take_while("[^%s;{}\"'/]"))
         if self:is_eof() then break end
         if self:peek_n(2) == "/*" then break end
         if self:peek_n(2) == "//" then break end
         if self:check("/") then
            table.insert(ret, "/")
         end
      until not self:check_pattern("[^%s;{}\"'/]")
      return table.concat(ret)
   end
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

   local returnval = { loc = self:loc() }

   -- Then must be a string that is the statement's identifier
   local keyword = self:parse_keyword()
   if keyword == "" then
      self:error("keyword expected")
   end
   returnval.keyword = keyword

   -- Take the identifier
   if self:skip_whitespace() and self:peek() ~= ';' and self:peek() ~= '{' then
      returnval.argument = self:parse_string()
      self:skip_whitespace()
   end

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

function parse_string(str, filename)
   local parser = Parser.new(mem.open_input_string(str, filename))
   parser:skip_whitespace()
   local str = parser:parse_string()
   parser:skip_whitespace()
   if not parser:is_eof() then parser:error("Not end of file") end
   return str
end

function parse_strings(str, filename)
   local parser = Parser.new(mem.open_input_string(str, filename))
   local ret = {}
   parser:skip_whitespace()
   while not parser:is_eof() do
      table.insert(ret, parser:parse_string())
      parser:skip_whitespace()
   end
   return ret
end

function parse_statement_lists(str, filename)
   local parser = Parser.new(mem.open_input_string(str, filename))
   local ret = {}
   parser:skip_whitespace()
   while not parser:is_eof() do
      parser:consume("{")
      table.insert(ret, parser:parse_statement_list())
      parser:consume("}")
      parser:skip_whitespace()
   end
   return ret
end

function parse(stream)
   local parser = Parser.new(stream)
   return parser:parse_module()
end

function selftest()
   local function assert_equal(a, b)
      if not lib.equal(a, b) then
         print(a, b)
         error("not equal")
      end
   end

   local function strip_locs(exp)
      if type(exp) ~= 'table' then return exp end
      local ret = {}
      for k, v in pairs(exp) do
         if k ~= 'loc' then ret[k] = strip_locs(v) end
      end
      return ret
   end

   local function test_string(src, exp)
      local parser = Parser.new(mem.open_input_string(src))
      parser:skip_whitespace()
      assert_equal(strip_locs(parser:parse_string()), exp)
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
      local result = strip_locs(parse(mem.open_input_string(src)))
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
   test_string("hello//world", "hello")
   test_string(lines("  'foo", "    bar'"), lines("foo", " bar"))
   test_string(lines("  'foo", "  bar'"), lines("foo", "bar"))
   test_string(lines("   'foo", "\tbar'"), lines("foo", "    bar"))
   test_string(lines("   'foo", " bar'"), lines("foo", "bar"))
   test_module("type;", {{keyword="type"}})
   test_module("type string;", {{keyword="type", argument="string"}})
   test_module("/** **/", {})
   test_module("  /** **/  ", {})
   test_module("// foo bar;", {})
   test_module("// foo bar;\nleaf port;", {{keyword="leaf", argument="port"}})
   test_module("type/** hellooo */string;", {{keyword="type", argument="string"}})
   test_module('type "hello\\pq";', {{keyword="type", argument="hello\\pq"}})
   test_module('description "";', {{keyword="description", argument=""}})
   test_module('description;', {{keyword="description"}})
   test_module('description ;', {{keyword="description"}})
   test_module(lines("leaf port {", "type number;", "}"), {{keyword="leaf",
   argument="port", statements={{keyword="type", argument="number"}}}})
   test_module(lines("leaf port {", "type;", "}"), {{keyword="leaf",
   argument="port", statements={{keyword="type"}}}})
   test_module('description hello/world;', {{keyword="description",
   argument="hello/world"}})
   parse(mem.open_input_string(require('lib.yang.ietf_inet_types_yang')))
   parse(mem.open_input_string(require('lib.yang.ietf_yang_types_yang')))
   parse(mem.open_input_string(require('lib.yang.ietf_softwire_common_yang')))
   parse(mem.open_input_string(require('lib.yang.ietf_softwire_br_yang')))
end
