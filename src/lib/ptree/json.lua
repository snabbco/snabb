-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

-- A very limited json library that only does objects of strings.

local function take_while(input, pat)
   local out = {}
   while input:peek_char() and input:peek_char():match(pat) do
      table.insert(out, input:read_char())
   end
   return table.concat(out)
end

local function drop_while(input, pat)
   take_while(input, pat)
end

local function skip_whitespace(input)
   local whitespace_pat = '[ \n\r\t]'
   drop_while(input, whitespace_pat)
end

local function check(input, ch)
   if input:peek_char() ~= ch then return false end
   input:read_char()
   return true
end

local function consume(input, expected)
   local ch = input:read_char()
   if ch == expected then return end
   if ch == nil then error('unexpected EOF') end
   error('expected '..expected..', got '..ch)
end

local function consume_pat(input, pat)
   local ch = input:read_char()
   if ch:match(pat) then return ch end
   if ch == nil then error('unexpected EOF') end
   error('unexpected character '..ch)
end

-- Pattern describing characters that can appear literally in a JSON
-- string.
local literal_string_chars_pat = '%w'
do
   -- Printable non-alphanumeric ASCII chars, excluding control
   -- characters, backslash, and double-quote.
   local punctuation = "!#$%&'()*+,-./:;<=>?@[]^_`{|}~ "
   for i=1,#punctuation do
      local punctuation_pat = '%'..punctuation:sub(i,i)
      literal_string_chars_pat = literal_string_chars_pat..punctuation_pat
   end
   literal_string_chars_pat = '['..literal_string_chars_pat..']'
end
-- The escapable characters in JSON.
local escaped_string_chars =
   { r="\r", n="\n", t="\t", ["\\"]="\\", ['"']='"', b="\b", f="\f", ["/"]="/" }

local function read_json_string(input)
   consume(input, '"')
   local parts = {}
   while not check(input, '"') do
      -- JSON strings support unicode.  The encoding of the JSON could
      -- be anything though UTF-8 is the likely one.  Assume the
      -- encoding is ASCII-compatible (like UTF-8) and restrict
      -- ourselves to printable ASCII characters.
      local part = take_while(input, literal_string_chars_pat)
      if part == '' then
         consume(input, "\\")
         for k,v in pairs(escaped_string_chars) do
            if check(input, k) then part = v; break end
         end
         if part == '' and check(input, "u") then
            -- 4-hex-digit unicode escape.  We only support ASCII
            -- tho.
            local hex = '0x'
            for i=1,4 do hex = hex..consume_pat(input, "%x") end
            local code = assert(tonumber(hex))
            if code >= 128 then error('non-ASCII character: \\u00'..hex) end
            part = string.char(code)
         end
      end
      table.insert(parts, part)
   end
   return table.concat(parts)
end

function read_json_object(input)
   skip_whitespace(input)
   -- Return nil on EOF.
   if input:peek_byte() == nil then return nil end
   consume(input, "{")
   skip_whitespace(input)
   local ret = {}
   if not check(input, "}") then
      repeat
         skip_whitespace(input)
         local k = read_json_string(input)
         if ret[k] then error('duplicate key: '..k) end
         skip_whitespace(input)
         consume(input, ":")
         skip_whitespace(input)
         local v = read_json_string(input)
         ret[k] = v
         skip_whitespace(input)
      until not check(input, ",")
      skip_whitespace(input)
      consume(input, "}")
   end
   return ret
end

local function write_json_string(output, str)
   output:write_chars('"')
   local pos = 1
   while pos <= #str do
      local head = str:match('^('..literal_string_chars_pat..'+)', pos)
      if head then
         output:write_chars(head)
         pos = pos + #head
      else
         head = str:sub(pos, pos)
         local escaped
         for k,v in pairs(escaped_string_chars) do
            if v == head then escaped = k; break end
         end
         if not escaped then
            escaped = string.format("u00%.2x", head:byte(1))
         end
         output:write_chars('\\'..escaped)
         pos = pos + 1
      end
   end
   output:write_chars('"')
end

function write_json_object(output, obj)
   output:write_chars('{')
   local comma = false
   for k,v in pairs(obj) do
      if comma then output:write_chars(',') else comma = true end
      write_json_string(output, k)
      output:write_chars(':')
      write_json_string(output, v)
   end
   output:write_chars('}')
end

function selftest ()
   print('selftest: lib.ptree.json')
   local equal = require('core.lib').equal
   local tmpfile = require('lib.stream.mem').tmpfile
   local function test_json(str, obj)
      local tmp = tmpfile()
      tmp:write(str)
      tmp:write(" ") -- whitespace sentinel on the end.
      for i = 1,2 do
         tmp:seek('set', 0)
         local parsed = read_json_object(tmp)
         assert(equal(parsed, obj))
         assert(read_json_object(tmp) == nil)
         assert(tmp:read_char() == nil)

         tmp = tmpfile()
         write_json_object(tmp, parsed)
         tmp:write(' ') -- sentinel
      end
   end
   test_json('{}', {})
   test_json('{"foo":"bar"}', {foo='bar'})
   test_json('{"foo":"bar","baz":"qux"}', {foo='bar', baz='qux'})
   test_json('{ "foo" : "bar" , "baz" : "qux" }',
             {foo='bar', baz='qux'})
   test_json('{ "fo\\u000ao" : "ba\\r " , "baz" : "qux" }',
             {['fo\no']='ba\r ', baz='qux'})
   print('selftest: ok')
end
