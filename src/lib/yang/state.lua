-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local lib = require("core.lib")
local shm = require("core.shm")
local yang = require("lib.yang.yang")
local data = require("lib.yang.data")
local util = require("lib.yang.util")
local counter = require("core.counter")

local function flatten(val, out)
   out = out or {}
   for k, v in pairs(val) do
      if type(v) == "table" then
         flatten(v, out)
      else
         out[k] = v
      end
   end
   return out
end

local function find_counters(pid)
   local path = '/'..pid..'/apps'
   local apps = {}
   for _, app in ipairs(shm.children(path)) do
      local counters = {}
      local app_path = path..'/'..app
      for _, file in ipairs(shm.children(app_path)) do
         local name, type = file:match("(.*)[.](.*)$")
         if type == 'counter' then
            counters[name] = counter.open(app_path..'/'..file)
         end
      end
      apps[app] = counters
   end
   return apps
end

function counters_for_pid(pid)
   return flatten(find_counters(pid))
end

function state_reader_from_grammar(production, maybe_keyword)
   local visitor = {}
   local function visit(keyword, production)
      return assert(visitor[production.type])(keyword, production)
   end
   local function visitn(productions)
      local ret = {}
      for keyword, production in pairs(productions) do
         ret[data.normalize_id(keyword)] = visit(keyword, production)
      end
      return ret
   end
   function visitor.list(keyword, production)
      -- TODO: Right now we basically map leaves to counters; we have
      -- no structured way to know what keys we might use.  To make
      -- tables here we'd need more of a design!
      -- io.stderr:write(
      --    'WARNING: Reading state into lists is not yet implemented\n')
      return function(counters) return nil end
   end
   function visitor.array(keyword, production)
      -- For similar reasons as tables, no idea what to do here!
      -- io.stderr:write(
      --    'WARNING: Reading state into arrays not yet implemented\n')
      return function(counters) return nil end
   end
   function visitor.struct(keyword, production)
      local readers = visitn(production.members)
      local function finish(x) return x end
      if production.ctype then finish = data.typeof(production.ctype) end
      return function(counters)
         local ret = {}
         for id, reader in pairs(readers) do
            ret[id] = reader(counters)
         end
         return finish(ret)
      end
   end
   function visitor.scalar(keyword, production)
      local default = production.default
      if default then
         local parse = data.value_parser(production.argument_type)
         default = parse(default, keyword)
      end
      return function(counters)
         local c = counters[keyword]
         if c then return counter.read(c) end
         return default
      end
   end
   return visit(maybe_keyword, production)
end
state_reader_from_grammar = util.memoize(state_reader_from_grammar)

function state_reader_from_schema(schema)
   local grammar = data.state_grammar_from_schema(schema)
   return state_reader_from_grammar(grammar)
end
state_reader_from_schema = util.memoize(state_reader_from_schema)

function state_reader_from_schema_by_name(schema_name)
   local schema = yang.load_schema_by_name(schema_name)
   return state_reader_from_schema(schema)
end
state_reader_from_schema_by_name = util.memoize(state_reader_from_schema_by_name)

function selftest ()
   print("selftest: lib.yang.state")
   local ffi = require("ffi")
   local simple_router_schema_src = [[module snabb-simple-router {
      namespace snabb:simple-router;
      prefix simple-router;

      import ietf-inet-types {prefix inet;}

      leaf active { type boolean; default true; }
      leaf-list blocked-ips { type inet:ipv4-address; }

      container routes {
         list route {
            key addr;
            leaf addr { type inet:ipv4-address; mandatory true; }
            leaf port { type uint8 { range 0..11; } mandatory true; }
         }
      }

      container state {
         config false;

         leaf total-packets {
            type uint64; default 0;
         }

         leaf dropped-packets {
            type uint64; default 0;
         }
      }

      grouping detailed-counters {
         leaf dropped-wrong-route {
            type uint64; default 0;
         }
         leaf dropped-not-permitted {
            type uint64; default 0;
         }
      }

      container detailed-state {
         config false;
         uses "detailed-counters";
      }
   }]]
   local simple_router_schema = yang.load_schema(simple_router_schema_src,
                                                 "state-test")
   local reader = state_reader_from_schema(simple_router_schema)
   local state = reader({
      ['total-packets'] = ffi.new("struct counter", {c=1}),
      ['dropped-packets'] = ffi.new("struct counter", {c=2}),
      ['dropped-wrong-route'] = ffi.new("struct counter", {c=3}),
      ['dropped-not-permitted'] = ffi.new("struct counter", {c=4})
   })
   assert(1 == state.state.total_packets)
   assert(2 == state.state.dropped_packets)
   assert(3 == state.detailed_state.dropped_wrong_route)
   assert(4 == state.detailed_state.dropped_not_permitted)
   print('selftest: ok')
end
