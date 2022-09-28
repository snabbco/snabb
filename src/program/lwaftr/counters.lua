module(..., package.seeall)

local counter = require("core.counter")
local schema = require('lib.yang.schema')
local data = require('lib.yang.data')
local state = require('lib.yang.state')
local S = require('syscall')

function counter_names ()
   local names = {}
   local schema = schema.load_schema_by_name('snabb-softwire-v3')
   for k, node in pairs(schema.body['softwire-state'].body) do
      if node.kind == 'leaf' then
         names[k] = data.normalize_id(k)
      end
   end
   return names
end

function read_counters (pid)
   local reader = state.state_reader_from_schema_by_name('snabb-softwire-v3')
   local s = reader(state.counters_for_pid(pid or S.getpid()))
   local ret = {}
   for k, id in pairs(counter_names()) do
      ret[k] = s.softwire_state[id]
   end
   return ret
end
