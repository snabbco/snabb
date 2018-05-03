-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local lib = require('core.lib')
local json = require("lib.ptree.json")

local Trace = {}
local trace_config_spec = {
   file = {required=true},
   file_mode = {default="w"},
}

function new (conf)
   local conf = lib.parse(conf, trace_config_spec)
   local ret = setmetatable({}, {__index=Trace})
   ret.id = 0
   ret.output = io.open(conf.file, conf.file_mode)
   return ret
end

local function listen_directive_for_rpc(rpc_id, args)
   local ret = { path=args.path, schema=args.schema, revision=args.revision }
   if rpc_id == 'get-config' then
      ret.verb = 'get'
      return ret
   elseif rpc_id == 'set-config' then
      ret.verb, ret.value = 'set', args.config
      return ret
   elseif rpc_id == 'add-config' then
      ret.verb, ret.value = 'add', args.config
      return ret
   elseif rpc_id == 'remove-config' then
      ret.verb = 'remove'
      return ret
   elseif rpc_id == 'get-state' then
      ret.verb = 'get-state'
      return ret
   else
      return nil
   end
end

function Trace:record(id, args)
   assert(self.output, "trace closed")
   local obj = listen_directive_for_rpc(id, args)
   if not obj then return end
   obj.id = tostring(self.id)
   self.id = self.id + 1
   json.write_json_object(self.output, obj)
   self.output:write('\n')
   self.output:flush()
end

function Trace:close()
   self.output:close()
   self.output = nil
end

function selftest ()
   print('selftest: lib.ptree.trace')
   local S = require('syscall')

   local tmp = os.tmpname()
   local trace = new({file=tmp})
   trace:record("get-config",
                {path="/", schema="foo", revision="bar"})
   trace:record("set-config",
                {path="/", schema="foo", revision="bar", config="baz"})
   trace:record("unsupported-rpc",
                {path="/", schema="foo", revision="bar", config="baz"})
   trace:close()

   local fd = S.open(tmp, 'rdonly')
   local input = json.buffered_input(fd)
   json.skip_whitespace(input)
   local parsed = json.read_json_object(input)
   assert(lib.equal(parsed, {id="0", verb="get", path="/",
                             schema="foo", revision="bar"}))
   json.skip_whitespace(input)
   parsed = json.read_json_object(input)
   assert(lib.equal(parsed, {id="1", verb="set", path="/",
                             schema="foo", revision="bar", value="baz"}))
   json.skip_whitespace(input)
   assert(input:eof())
   fd:close()
   os.remove(tmp)

   print('selftest: ok')
end
