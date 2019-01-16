-- Use of this source code is governed by the Apache 2.0 license; see
-- COPYING.
module(..., package.seeall)

local schema = require("lib.yang.schema")
local data = require("lib.yang.data")
local mem = require("lib.stream.mem")

function prepare_callee(schema_name)
   local schema = schema.load_schema_by_name(schema_name)
   return {
      parse_input = data.rpc_input_parser_from_schema(schema),
      print_output = data.rpc_output_printer_from_schema(schema)
   }
end

function prepare_caller(schema_name)
   local schema = schema.load_schema_by_name('snabb-config-leader-v1')
   return {
      print_input = data.rpc_input_printer_from_schema(schema),
      parse_output = data.rpc_output_parser_from_schema(schema)
   }
end

function prepare_calls(caller, calls, call_stream)
   caller.print_input(calls, call_stream)
   local function parse_responses(stream)
      local responses = caller.parse_output(stream)
      assert(#responses == #calls)
      local stripped_responses = {}
      for i=1,#calls do
         assert(responses[i].id == calls[i].id)
         table.insert(stripped_responses, responses[i].data)
      end
      return stripped_responses
   end
   return parse_responses
end

function prepare_call(caller, id, data)
   local call_stream = mem.tmpfile()
   local parse_responses = prepare_calls(caller, {{id=id, data=data}},
                                         call_stream)
   local function parse_response(stream) return parse_responses(stream)[1] end
   call_stream:seek('set', 0)
   return call_stream:read_all_chars(), parse_response
end

function handle_calls(callee, call_stream, handle, response_stream)
   local responses = {}
   for _,call in ipairs(callee.parse_input(call_stream)) do
      table.insert(responses,
                   { id=call.id, data=handle(call.id, call.data) })
   end
   callee.print_output(responses, response_stream)
end

function dispatch_handler(obj, prefix, trace)
   prefix = prefix or 'rpc_'
   local normalize_id = data.normalize_id
   return function(id, data)
      if trace then trace:record(id, data) end
      local id = prefix..normalize_id(id)
      local f = assert(obj[id], 'handler not found: '..id)
      return f(obj, data)
   end
end

function selftest()
   print('selftest: lib.yang.rpc')
   local caller = prepare_caller('snabb-config-leader-v1')
   local callee = prepare_callee('snabb-config-leader-v1')
   local data = { schema = 'foo' }
   local call_str, parse_response = prepare_call(caller, 'get-config', data)
   local handler = {}
   function handler:rpc_get_config(data)
      return { config='pong '..data.schema }
   end
   local response_stream = mem.tmpfile()
   handle_calls(callee, mem.open_input_string(call_str),
                dispatch_handler(handler), response_stream)
   response_stream:seek('set', 0)
   local response = parse_response(response_stream)
   assert(response.config == 'pong foo')
   print('selftest: ok')
end
