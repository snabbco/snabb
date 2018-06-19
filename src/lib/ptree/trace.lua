-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local lib = require('core.lib')
local stream = require("lib.stream")
local file = require("lib.stream.file")
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
   if stream.is_stream(conf.file) then
      ret.output = conf.file
   else
      ret.output = file.open(conf.file, conf.file_mode)
   end
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
   json.write_json(self.output, obj)
   self.output:write('\n')
   self.output:flush()
end

function Trace:close()
   self.output:close()
   self.output = nil
end

function selftest ()
   print('selftest: lib.ptree.trace')
   local tmp = require('lib.stream.mem').tmpfile()
   local trace = new({file=tmp})
   trace:record("get-config",
                {path="/", schema="foo", revision="bar"})
   trace:record("set-config",
                {path="/", schema="foo", revision="bar", config="baz"})
   trace:record("unsupported-rpc",
                {path="/", schema="foo", revision="bar", config="baz"})

   tmp:seek('set', 0)
   local parsed = json.read_json(tmp)
   assert(lib.equal(parsed, {id="0", verb="get", path="/",
                             schema="foo", revision="bar"}))
   parsed = json.read_json(tmp)
   assert(lib.equal(parsed, {id="1", verb="set", path="/",
                             schema="foo", revision="bar", value="baz"}))
   assert(json.read_json(tmp) == nil)
   assert(tmp:read_char() == nil)

   print('selftest: ok')
end
