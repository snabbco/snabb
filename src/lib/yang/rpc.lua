-- Use of this source code is governed by the Apache 2.0 license; see
-- COPYING.
module(..., package.seeall)

local schema = require("lib.yang.schema")
local data = require("lib.yang.data")
local util = require("lib.yang.util")

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

function prepare_calls(caller, calls)
   local str = caller.print_input(calls, util.string_output_file())
   local function parse_responses(str)
      local responses = caller.parse_output(str)
      assert(#responses == #calls)
      local stripped_responses = {}
      for i=1,#calls do
         assert(responses[i].id == calls[i].id)
         table.insert(stripped_responses, responses[i].data)
      end
      return stripped_responses
   end
   return str, parse_responses
end

function prepare_call(caller, id, data)
   local str, parse_responses = prepare_calls(caller, {{id=id, data=data}})
   local function parse_response(str) return parse_responses(str)[1] end
   return str, parse_response
end

function handle_calls(callee, str, handle)
   local responses = {}
   for _,call in ipairs(callee.parse_input(str)) do
      table.insert(responses,
                   { id=call.id, data=handle(call.id, call.data) })
   end
   return callee.print_output(responses, util.string_output_file())
end

function dispatch_handler(obj, prefix)
   prefix = prefix or 'rpc_'
   local normalize_id = data.normalize_id
   return function(id, data)
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
   local response_str = handle_calls(callee, call_str,
                                     dispatch_handler(handler))
   local response = parse_response(response_str)
   assert(response.config == 'pong foo')
   print('selftest: ok')
end
