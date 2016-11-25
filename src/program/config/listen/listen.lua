-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local rpc = require("lib.yang.rpc")
local data = require("lib.yang.data")
local path_lib = require("lib.yang.path")
local common = require("program.config.common")

local function buffered_input_from_fd(fd)
   local buf_size = 4096
   local buf = ffi.new('uint8_t[?]', buf_size)
   local buf_end = 0
   local pos = 0
   local ret = {}
   local eof = false
   local function fill()
      assert(pos == buf_end)
      if eof then return 0 end
      pos = 0
      buf_end = assert(S.read(fd, buf, buf_size))
      assert(0 <= buf_end and buf_end <= buf_size)
      if buf_end == 0 then eof = true end
      return buf_end
   end
   function ret:avail() return buf_end - pos end
   function ret:getfd() return fd end
   function ret:eof() return eof end
   function ret:peek()
      if pos == buf_end and fill() == 0 then return nil end
      return string.char(buf[pos])
   end
   function ret:discard()
      assert(pos < buf_end)
      pos = pos + 1
   end
   return ret
end

local whitespace_pat = '[ \n\r\t]'

local function drop_buffered_whitespace(input)
   while input:avail() > 0 and input:peek():match(whitespace_pat) do
      input:discard()
   end
end

local function take_while(input, pat)
   local out = {}
   while input:peek() and input:peek():match(pat) do
      table.insert(out, input:peek())
      input:discard()
   end
   return table.concat(out)
end

local function check(input, ch)
   if input:peek() ~= ch then return false end
   input:discard()
   return true
end

local function consume(input, ch)
   if not check(input, ch) then
      if input:eof() then error('unexpected EOF') end
      error('expected '..ch..', got '..input:peek())
   end
end

local function consume_pat(input, pat)
   local ch = input:peek()
   if ch == nil then error('unexpected EOF') end
   if not ch:match(pat) then error('unexpected character '..ch) end
   input:discard()
   return ch
end

local function skip_whitespace(input) take_while(input, whitespace_pat) end

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

local function read_json_object(input)
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

local function buffered_output()
   local ret = { buf = {} }
   function ret:write(str) table.insert(self.buf, str) end
   function ret:flush_to_fd(fd)
      local str = table.concat(self.buf)
      local bytes = ffi.new('uint8_t[?]', #str, str)
      local written = 0
      while written < #str do
         local wrote = assert(S.write(fd, bytes + written, #str - written))
         written = written + wrote
      end
   end
   return ret
end

local function write_json_string(output, str)
   output:write('"')
   local pos = 1
   while pos <= #str do
      local head = str:match('^('..literal_string_chars_pat..'+)', pos)
      if head then
         output:write(head)
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
         output:write('\\'..escaped)
         pos = pos + 1
      end
   end
   output:write('"')
end

local function write_json_object(output, obj)
   output:write('{')
   local comma = false
   for k,v in pairs(obj) do
      if comma then output:write(',') else comma = true end
      write_json_string(output, k)
      output:write(':')
      write_json_string(output, v)
   end
   output:write('}')
end

local function validate_value(schema_name, revision_date, path, value_str)
   local parser = common.data_parser(schema_name, path)
   local value = parser(value_str)
   return common.serialize_config(value, schema_name, path)
end

local request_handlers = {}
function request_handlers.get(schema_name, revision_date, path)
   return {method='get-config',
           args={schema=schema_name, revision=revision_date, path=path}}
end
function request_handlers.get_state(schema_name, revision_date, path)
   return {method='get-state',
           args={schema=schema_name, revision=revision_date, path=path}}
end
function request_handlers.set(schema_name, revision_date, path, value)
   assert(value ~= nil)
   local config = validate_value(schema_name, revision_date, path, value)
   return {method='set-config',
           args={schema=schema_name, revision=revision_date, path=path,
                 config=config}}
end
function request_handlers.add(schema_name, revision_date, path, value)
   assert(value ~= nil)
   local config = validate_value(schema_name, revision_date, path, value)
   return {method='add-config',
           args={schema=schema_name, revision=revision_date, path=path,
                 config=config}}
end
function request_handlers.remove(schema_name, revision_date, path)
   return {method='remove-config',
           args={schema=schema_name, revision=revision_date, path=path}}
end

local function read_request(client, schema_name, revision_date)
   local json = read_json_object(client)
   local id, verb, path = assert(json.id), assert(json.verb), assert(json.path)
   path = path_lib.normalize_path(path)
   local handler = assert(request_handlers[data.normalize_id(verb)])
   local req = handler(schema_name, revision_date, path, json.value)
   local function print_reply(reply)
      local output = buffered_output()
      write_json_object(output, {id=id, status='ok', value=reply.config})
      output:flush_to_fd(1) -- stdout
   end
   return req, print_reply
end

local function attach_listener(leader, caller, schema_name, revision_date)
   local msg, parse_reply = rpc.prepare_call(
      caller, 'attach-listener', {schema=schema_name, revision=revision_date})
   common.send_message(leader, msg)
   return parse_reply(common.recv_message(leader))
end

function run(args)
   args = common.parse_command_line(args, { command='listen' })
   local caller = rpc.prepare_caller('snabb-config-leader-v1')
   local leader = common.open_socket_or_die(args.instance_id)
   attach_listener(leader, caller, args.schema_name, args.revision_date)
   local client = buffered_input_from_fd(0) -- stdin
   local pollfds = S.types.t.pollfds({
         {fd=leader, events="in"},
         {fd=client, events="in"}})
   local pending_replies = {}
   while true do
      if client:avail() == 0 then
         assert(S.poll(pollfds, -1))
      end
      for _,pfd in ipairs(pollfds) do
         if pfd.fd == leader:getfd() then
            if pfd.ERR or pfd.HUP then
               while #pending_replies > 0 do
                  local have_reply = table.remove(pending_replies)
                  have_reply(common.recv_message(leader))
               end
               io.stderr:write('Leader hung up\n')
               main.exit(1)
            elseif pfd.IN then
               assert(#pending_replies > 0)
               local have_reply = table.remove(pending_replies)
               have_reply(common.recv_message(leader))
            end
            pfd.revents = 0
         elseif pfd.fd == client:getfd() then
            if pfd.ERR or pfd.HUP or pfd.NVAL then
               io.stderr:write('Client hung up\n')
               main.exit(0)
            end
            if pfd.IN then
               -- The JSON objects sent to us by the client can have
               -- whitespace between them.  Make sure we don't block
               -- expecting a new datum when really it was just the
               -- remote side sending whitespace.  (Calling peek()
               -- causes the buffer to fill, which itself shouldn't
               -- block given the IN flag in the revents.)
               client:peek()
               drop_buffered_whitespace(client)
            end
            while client:avail() > 0 do
               local request, print_reply =
                  read_request(client, args.schema_name, args.revision_date)
               drop_buffered_whitespace(client)
               local msg, parse_reply = rpc.prepare_call(
                  caller, request.method, request.args)
               local function have_reply(msg)
                  return print_reply(parse_reply(msg))
               end
               common.send_message(leader, msg)
               table.insert(pending_replies, 1, have_reply)
            end
            pfd.revents = 0
         else
            error('unreachable')
         end
      end
   end
end

function selftest ()
   print('selftest: program.config.listen.listen')
   local equal = require('core.lib').equal
   local function test_json(str, obj)
      local tmp = os.tmpname()
      local f = io.open(tmp, 'w')
      f:write(str)
      f:write(" ") -- whitespace sentinel on the end.
      f:close()
      for i = 1,2 do
         local fd = S.open(tmp, 'rdonly')
         local input = buffered_input_from_fd(fd)
         local parsed = read_json_object(input)
         assert(equal(parsed, obj))
         assert(not input:eof())
         assert(check(input, " "))
         assert(not input:peek())
         assert(input:eof())
         fd:close()

         local fd = assert(S.open(tmp, 'wronly, trunc'))
         local output = buffered_output()
         write_json_object(output, parsed)
         output:write(' ') -- sentinel
         output:flush_to_fd(fd)
         fd:close()
      end
      os.remove(tmp)
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
