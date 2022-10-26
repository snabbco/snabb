-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local data = require("lib.yang.data")
local value = require("lib.yang.value")
local schema = require("lib.yang.schema")
local parse_path = require("lib.yang.path").parse_path
local util = require("lib.yang.util")
local list = require("lib.yang.list")
local normalize_id = data.normalize_id

local function table_keys(t)
   local ret = {}
   for k, v in pairs(t) do table.insert(ret, k) end
   return ret
end

function prepare_array_lookup(query)
   if not lib.equal(table_keys(query), {"position()"}) then
      error("Invalid query: leaf-list can only be indexed by position.")
   end
   local idx = tonumber(query["position()"])
   if idx < 1 or idx ~= math.floor(idx) then
      error("Invalid query: leaf-list can only be indexed by positive integers.")
   end
   return idx
end

function prepare_list_lookup(grammar, query)
   if not grammar.list.has_key then
      error("Invalid query: list has no key.")
   end
   local key = {}
   for k,_ in pairs(query) do
      if not grammar.keys[k] then
         error("Invalid path:'"..k.."' is not a list key.")
      end
   end
   for k,grammar in pairs(grammar.keys) do
      local v = query[k] or grammar.default
      if v == nil then
         error("Invalid query: missing required key '"..k.."'")
      end
      local key_primitive_type = grammar.argument_type.primitive_type
      local parser = value.types[key_primitive_type].parse
      key[normalize_id(k)] = parser(v, 'path query value')
   end
   return key
end

local function compute_struct_getter(grammar, name, getter)
   local child_grammar = grammar.members[name]
   if not child_grammar then
      for member_name, member in pairs(grammar.members) do
         if child_grammar then break end
         if member.type == 'choice' then
            for case_name, case in pairs(member.choices) do
               if child_grammar then break end
               if case[name] then child_grammar = case[name] end
            end
         end
      end
   end
   if not child_grammar then
      error("Struct has no field named '"..name.."'.")
   end
   local id = normalize_id(name)
   local function child_getter(data)
      local struct = getter(data)
      local child = struct[id]
      if child == nil then
         error("Struct instance has no field named '"..name.."'.")
      end
      return child
   end
   return child_grammar, child_getter
end

local function compute_array_getter(grammar, query, getter)
   local idx = prepare_array_lookup(query)
   -- Pretend that array elements are scalars.
   local child_grammar = {type="scalar", argument_type=grammar.element_type,
                          ctype=grammar.ctype}
   local function child_getter(data)
      local array = getter(data)
      if idx > #array then error("Index out of bounds") end
      return array[idx]
   end
   return child_grammar, child_getter
end

local function compute_list_getter(grammar, query, getter)
   local key = prepare_list_lookup(grammar, query)
   -- Pretend that list entries are structs.
   local child_grammar = {type="struct", members=grammar.values,
                          ctype=grammar.value_ctype}
   local function child_getter(data)
      local l = list.object(getter(data))
      local data = l:find_entry(key)
      if data == nil then error("Not found") end
      return data
   end
   return child_grammar, child_getter
end

local function compute_getter(grammar, name, query, getter)
   if grammar.type == 'struct' then
      grammar, getter = compute_struct_getter(grammar, name, getter)
   else
      error("Invalid path: '"..name.."' is not a container.")
   end
   if #table_keys(query) > 0 then
      if grammar.type == 'array' then
         return compute_array_getter(grammar, query, getter)
      elseif grammar.type == 'list' then
         return compute_list_getter(grammar, query, getter)
      else
         error("Invalid path: '"..name.."' can not be queried.")
      end
   end
end

-- Returns a resolver for a particular schema and *lua* path.
function resolver(grammar, path)
   if type(path) == 'string' then
      path = parse_path(path)
   end
   local getter = function(data) return data end
   for _, elt in ipairs(path) do
      getter, grammar = compute_getter(grammar, elt.name, elt.query, getter)
   end
   return getter, grammar
end

resolver = util.memoize(resolver)

local function printer_for_grammar(grammar, path, format, print_default)
   local getter, subgrammar = resolver(grammar, path)
   local printer
   if format == "xpath" then
      printer = data.xpath_printer_from_grammar(subgrammar, print_default, path)
   elseif format == "influxdb" then
      printer = data.influxdb_printer_from_grammar(subgrammar, print_default, path)
   else
      printer = data.data_printer_from_grammar(subgrammar, print_default)
   end
   return function(data, file)
      return printer(getter(data), file)
   end
end

local function printer_for_schema(schema, path, is_config, format,
                                  print_default)
   local grammar = data.data_grammar_from_schema(schema, is_config)
   return printer_for_grammar(grammar, path, format, print_default)
end

function printer_for_schema_by_name(schema_name, path, is_config, format,
                                    print_default)
   local schema = schema.load_schema_by_name(schema_name)
   return printer_for_schema(schema, path, is_config, format, print_default)
end
printer_for_schema_by_name = util.memoize(printer_for_schema_by_name)

local function parser_for_grammar(grammar, path)
   local getter, subgrammar = resolver(grammar, path)
   return function (production)
      local data = data.data_parser_from_grammar(subgrammar)(production)
      consistency_checker_from_grammar(subgrammar)(data)
      return data
   end
end

local function parser_for_schema(schema, path)
   local grammar = data.config_grammar_from_schema(schema)
   return parser_for_grammar(grammar, path)
end

function parser_for_schema_by_name(schema_name, path)
   return parser_for_schema(schema.load_schema_by_name(schema_name), path)
end
parser_for_schema_by_name = util.memoize(parser_for_schema_by_name)

local function setter_for_grammar(grammar, path)
   if path == "/" then
      return function(config, subconfig) return subconfig end
   end
   local head = parse_path(path)
   local tail = table.remove(head)
   local tail_name, query = tail.name, tail.query
   if lib.equal(query, {}) then
      -- No query; the simple case.
      local getter, grammar = resolver(grammar, head)
      if grammar.type ~= 'struct' then
         error("Invalid path: missing query for '"..tail_name.."'.")
      end
      local tail_id = data.normalize_id(tail_name)
      return function(config, subconfig)
         getter(config)[tail_id] = subconfig
         return config
      end
   end

   -- Otherwise the path ends in a query; it must denote an array or
   -- table item.
   table.insert(head, {name=tail_name, query={}})
   local getter, grammar = resolver(grammar, head)
   if grammar.type == 'array' then
      local idx = prepare_array_lookup(query)
      return function(config, subconfig)
         local array = getter(config)
         array[idx] = subconfig
         return config
      end
   elseif grammar.type == 'list' then
      local key = prepare_list_lookup(grammar, query)
      return function (config, subconfig)
         local l = list.object(getter(config))
         l:add_or_update_entry(key, subconfig)
         return config
      end
   else
      error("Invalid path: '"..tail_name.."' can not be queried.")
   end
end

local function setter_for_schema(schema, path)
   local grammar = data.config_grammar_from_schema(schema)
   return setter_for_grammar(grammar, path)
end

function setter_for_schema_by_name(schema_name, path)
   return setter_for_schema(schema.load_schema_by_name(schema_name), path)
end
setter_for_schema_by_name = util.memoize(setter_for_schema_by_name)

local function adder_for_grammar(grammar, path)
   local top_grammar = grammar
   local getter, grammar = resolver(grammar, path)
   if grammar.type == 'array' then
      return function(config, subconfig)
         local cur = getter(config)
         for _,elt in ipairs(subconfig) do
            cur[#cur+1] = elt
         end
         return config
      end
   elseif grammar.type == 'list' then
      -- Invariant: either all entries in the new subconfig are added,
      -- or none are.
      return function(config, subconfig)
         local l = list.object(getter(config))
         for i, entry in ipairs(subconfig) do
            if l:find_entry(entry) then
               error("Can not add already-existing list entry #"..i..".")
            end
         end
         for _, entry in ipairs(subconfig) do
            l:add_entry(entry)
         end
         return config
      end
   else
      error("Invalid path: '"..tail_name.."' is not a list or a leaf-list.")
   end
end

local function adder_for_schema(schema, path)
   local grammar = data.config_grammar_from_schema(schema)
   return adder_for_grammar(grammar, path)
end

function adder_for_schema_by_name (schema_name, path)
   return adder_for_schema(schema.load_schema_by_name(schema_name), path)
end
adder_for_schema_by_name = util.memoize(adder_for_schema_by_name)

local function remover_for_grammar(grammar, path)
   local top_grammar = grammar
   local head = parse_path(path)
   local tail = table.remove(head)
   local tail_name, query = tail.name, tail.query
   table.insert(head, {name=tail_name, query={}})
   local getter, grammar = resolver(grammar, head)
   if grammar.type == 'array' then
      local idx = prepare_array_lookup(query)
      return function(config)
         local cur = getter(config)
         if idx > #cur then
            error("Leaf-list '"..tail_name"' has no element #"..idx..".")
         end
         cur[idx] = nil
         return config
      end
   elseif grammar.type == 'list' then
      local key = prepare_list_lookup(grammar, query)
      return function(config)
         local l = list.object(getter(config))
         if not l:remove_entry(key) then
            error("List '"..tail_name"' has no entry matching the query.")
         end
         return config
      end
   else
      error("Invalid path: '"..tail_name.."' is not a list or a leaf-list.")
   end
end

local function remover_for_schema(schema, path)
   local grammar = data.config_grammar_from_schema(schema)
   return remover_for_grammar(grammar, path)
end

function remover_for_schema_by_name (schema_name, path)
   return remover_for_schema(schema.load_schema_by_name(schema_name), path)
end
remover_for_schema_by_name = util.memoize(remover_for_schema_by_name)

function leafref_checker_from_grammar(grammar)
   -- Converts a relative path to an absolute path.
   -- TODO: Consider moving it to /lib/yang/path.lua.
   local function to_absolute_path (path, node_path)
      path = path:gsub("current%(%)", node_path)
      if path:sub(1, 1) == '/' then return path end
      if path:sub(1, 2) == './' then
         path = path:sub(3)
         return node_path..'/'..path
      end
      while path:sub(1, 3) == '../' do
         path = path:sub(4)
         node_path = lib.dirname(node_path)
      end
      return node_path..'/'..path
   end
   local function leafref (node)
      return node.argument_type and node.argument_type.leafref
   end
   -- Leafref nodes iterator. Returns node as value and full data path as key.
   local function visit_leafref_paths (root)
      local function visit (path, node)
         if node.type == 'struct' then
            for k,v in pairs(node.members) do visit(path..'/'..k, v) end
         elseif node.type == 'array' then
            -- Pass.
         elseif node.type == 'scalar' then
            if leafref(node) then
               coroutine.yield(path, node)
            else
               -- Pass.
            end
         elseif node.type == 'list' then
            for k,v in pairs(node.keys) do visit(path..'/'..k, v) end
            for k,v in pairs(node.values) do visit(path..'/'..k, v) end
         elseif node.type == 'choice' then
            for _,choice in pairs(node.choices) do
               for k,v in pairs(choice) do visit(path..'/'..k, v) end
            end
         else
            error('unexpected kind', node.kind)
         end
      end
      return coroutine.wrap(function() visit('', root) end), true
   end
   -- Fetch value of path in data tree.
   local function resolve (data, path)
      local ret = data
      for k in path:gmatch("[^/]+") do ret = ret[k] end
      return ret
   end
   -- If not present, should be true.
   local function require_instance (node)
      if node.argument_type.require_instances == nil then return true end
      return node.argument_type.require_instances
   end
   local leafrefs = {}
   for path, node in visit_leafref_paths(grammar) do
      if require_instance(node) then
         local leafref = to_absolute_path(leafref(node), path)
         local success, getter = pcall(resolver, grammar, lib.dirname(leafref))
         if success then
            table.insert(leafrefs, {path=path, leafref=leafref, getter=getter})
         end
      end
   end
   if #leafrefs == 0 then return function(data) end end
   return function (data)
      for _,v in ipairs(leafrefs) do
         local path, leafref, getter = v.path, v.leafref, v.getter
         local results = assert(getter(data),
                                'Wrong XPath expression: '..leafref)
         local val = resolve(data, path)
         assert(type(results) == 'table' and results[val],
               ("Broken leafref integrity in '%s' when referencing '%s'"):format(
                path, leafref))
      end
   end
end

local function expanded_pairs(values)
   -- Return an iterator for each non-choice pair in values and each pair of
   -- all choice bodies recursively.
   local expanded = {}
   local function expand(values)
      for name, value in pairs(values) do
         if value.type == 'choice' then
            for _, body in pairs(value.choices) do
               expand(body)
            end
         else
            expanded[name] = value
         end
      end
   end
   expand(values)
   return pairs(expanded)
end

function uniqueness_checker_from_grammar(grammar)
   local function collision_checker(unique)
      local leaves = {}
      for leaf in unique:split(" +") do
         table.insert(leaves, normalize_id(leaf))
      end
      return function (x, y)
         local collision = true
         for _, leaf in ipairs(leaves) do
            if not lib.equal(x[leaf], y[leaf]) then
               collision = false
               break
            end
         end
         return collision
      end
   end
   local function uniqueness_checker (collsion)
      return function (list)
         -- Sad quadratic loop
         for i, x in ipairs(list) do
            for j, y in ipairs(list) does
               if i == j then break end
               if collision(x, y) then
                  return false
               end
            end
         end
         return true
      end
   end
   local function struct_getter (name)
      local id = normalize_id(name)
      return function(data)
         return data[id]
      end
   end
   local function visitor(grammar, getter)
      if grammar.type == 'struct' then
         local member_visitors = {}
         for name, member in expanded_pairs(grammar.members) do
            local visit_member = visitor(member, struct_getter(name))
            if visit_member then
               table.insert(member_visitors, visit_member)
            end
         end
         return function (data)
            local struct = getter(data)
            if not struct then return end
            -- visit members
            for _, visit in ipairs(member_visitors) do
               visit(struct)
            end
         end
      elseif grammar.type == 'list' then
         local value_visitors = {}
         for name, value in expanded_pairs(grammar.values) do
            local visit_value = visitor(value, struct_getter(name))
            if visit_value then
               table.insert(value_visitors, visit_value)
            end
         end
         local checkers = {}
         for _, unique in ipairs(grammar.unique) do
            checkers[unique] = uniqueness_checker(collision_checker(unique))
         end
         return function (data)
            local list = getter(data)
            if not list then return end
            -- visit values (skip if list has no list or container members)
            if #value_visitors > 0 then
               for _, entry in ipairs(list) do
                  for _, visit in ipairs(value_visitors) do
                     visit(entry)
                  end
               end
            end
            -- check uniqueness
            for unique, checker in ipairs(checkers) do
               if not checker(list) then
                  error("Not unique: "..unique)
               end
            end
         end
      end
   end
   return visitor(grammar, function (data) return data end)
end

function minmax_elements_checker_from_grammar(grammar)
   -- Generate checker for table (list, leaf-list)
   local function minmax_assertion(grammar, name)
      name = name or ""
      if not (grammar.min_elements or grammar.max_elements) then
         return function () end
      end
      return function (data)
         local n = #data
         if grammar.min_elements then
            assert(n >= grammar.min_elements,
                   name..": requires at least "..
                      grammar.min_elements.." element(s)")
         end
         if grammar.max_elements then
            assert(n <= grammar.max_elements,
                   name..": must not have more than "..
                      grammar.max_elements.." element(s)")
         end
      end
   end
   -- Visit tables with unique constraints in grammar and apply checker
   local function visit_minmax_and_check(grammar, data, name)
      if not data then return
      elseif grammar.type == 'array' then
         -- check min/max elements restrictions
         minmax_assertion(grammar, name)(data)
      elseif grammar.type == 'list' then
         -- visit values
         for name, value in expanded_pairs(grammar.values) do
            for _, datum in ipairs(data) do
               visit_minmax_and_check(value, datum[normalize_id(name)], name)
            end
         end
         -- check min/max elements restrictions
         minmax_assertion(grammar, name)(data)
      elseif grammar.type == 'struct' then
         -- visit members
         for name, member in expanded_pairs(grammar.members) do
            visit_minmax_and_check(member, data[normalize_id(name)], name)
         end
      end
   end
   return function (data)
      visit_minmax_and_check(grammar, data)
   end
end

function consistency_checker_from_grammar(grammar)
   return function (data)
      leafref_checker_from_grammar(grammar)(data)
      uniqueness_checker_from_grammar(grammar)(data)
      minmax_elements_checker_from_grammar(grammar)(data)
   end
end

function consistency_checker_from_schema(schema, is_config)
   local grammar = data.data_grammar_from_schema(schema, is_config)
   return consistency_checker_from_grammar(grammar)
end
consistency_checker_from_schema = util.memoize(consistency_checker_from_schema)

function consistency_checker_from_schema_by_name (schema_name, is_config)
   local schema = schema.load_schema_by_name(schema_name)
   local grammar = data.data_grammar_from_schema(schema, is_config)
   return consistency_checker_from_grammar(grammar)
end
consistency_checker_from_schema = util.memoize(consistency_checker_from_schema)

function selftest()
   print("selftest: lib.yang.path_data")
   local mem = require('lib.stream.mem')
   local schema_src = [[module snabb-simple-router {
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
      }}]]

   local scm = schema.load_schema(schema_src, "xpath-test")
   local grammar = data.config_grammar_from_schema(scm)

   -- Test resolving a key to a path.
   local data_src = mem.open_input_string [[
      active true;

      blocked-ips 8.8.8.8;
      blocked-ips 8.8.4.4;

      routes {
         route { addr 1.2.3.4; port 2; }
         route { addr 2.3.4.5; port 2; }
         route { addr 255.255.255.255; port 7; }
      }
   ]]

   local d = data.load_config_for_schema(scm, data_src)

   -- Try resolving a path in a list (ctable).
   local getter = resolver(grammar, "/routes/route[addr=1.2.3.4]/port")
   assert(getter(d) == 2)

   local getter = resolver(grammar, "/routes/route[addr=255.255.255.255]/port")
   assert(getter(d) == 7)

   -- Try resolving a leaf-list
   local getter = resolver(grammar, "/blocked-ips[position()=1]")
   assert(getter(d) == util.ipv4_pton("8.8.8.8"))

   -- Try resolving a path for a list (non-ctable)
   local fruit_schema_src = [[module fruit-bowl {
      namespace snabb:fruit-bowl;
      prefix simple-router;

      import ietf-inet-types {prefix inet;}

      container bowl {
         list fruit {
            key name;
            leaf name { type string; mandatory true; }
            leaf rating { type uint8 { range 0..10; } mandatory true; }
            choice C {
               case A { leaf AA { type string; } }
               case B { leaf BB { type string; } }
            }
         }
      }}]]
   local fruit_data_src = mem.open_input_string [[
      bowl {
         fruit { name "banana"; rating 10; }
         fruit { name "pear"; rating 2; }
         fruit { name "apple"; rating 6; }
         fruit { name "kumquat"; rating 6; AA aa; }
         fruit { name "tangerine"; rating 6; BB bb; }
      }
   ]]

   local fruit_scm = schema.load_schema(fruit_schema_src, "xpath-fruit-test")
   local fruit_prod = data.config_grammar_from_schema(fruit_scm)
   local fruit_data = data.load_config_for_schema(fruit_scm, fruit_data_src)

   local getter = resolver(fruit_prod, "/bowl/fruit[name=banana]/rating")
   assert(getter(fruit_data) == 10)

   local getter = resolver(fruit_prod, "/bowl/fruit[name=apple]/rating")
   assert(getter(fruit_data) == 6)

   local getter = resolver(fruit_prod, "/bowl/fruit[name=kumquat]/AA")
   assert(getter(fruit_data) == 'aa')

   local getter = resolver(fruit_prod, "/bowl/fruit[name=tangerine]/BB")
   assert(getter(fruit_data) == 'bb')

   -- Test leafref.
   local leafref_schema = [[module test-schema {
      yang-version 1.1;
      namespace urn:ietf:params:xml:ns:yang:test-schema;
      prefix test;

      import ietf-inet-types { prefix inet; }
      import ietf-yang-types { prefix yang; }

      container test {
         list interface {
            key "name";
            leaf name {
               type string;
            }
            leaf admin-status {
               type boolean;
               default false;
            }
            list address {
               key "ip";
               leaf ip {
                  type inet:ipv4-address;
               }
            }
         }
         leaf mgmt {
            type leafref {
               path "../interface/name";
            }
         }
      }
   }]]
   local my_schema = schema.load_schema(leafref_schema)
   local loaded_data = data.load_config_for_schema(my_schema, mem.open_input_string([[
   test {
      interface {
         name "eth0";
         admin-status true;
         address {
            ip 192.168.0.1;
         }
      }
      mgmt "eth0";
   }
   ]]))
   local checker = consistency_checker_from_schema(my_schema, true)
   checker(loaded_data)

   local checker = consistency_checker_from_schema_by_name('ietf-alarms', false)
   assert(checker)

   local scm = schema.load_schema_by_name('snabb-softwire-v3')
   local grammar = data.config_grammar_from_schema(scm)
   setter_for_grammar(grammar, "/softwire-config/instance[device=test]/"..
                               "queue[id=0]/external-interface/ip 208.118.235.148")
   remover_for_grammar(grammar, "/softwire-config/instance[device=test]/")

   -- Test unique restrictions:
   local unique_schema = schema.load_schema([[module unique-schema {
      namespace "urn:ietf:params:xml:ns:yang:unique-schema";
      prefix "test";

      list unique_test {
        key "testkey"; unique "testleaf testleaf2";
        leaf testkey { type string; mandatory true; }
        leaf testleaf { type string; mandatory true; }
        leaf testleaf2 { type string; mandatory true; }
      }
   }]])
   local checker = consistency_checker_from_schema(unique_schema, true)

   -- Test unique validation (should fail)
   local success, result = pcall(
      checker,
      data.load_config_for_schema(unique_schema,
                                  mem.open_input_string [[
                                     unique_test {
                                       testkey "foo";
                                       testleaf "bar";
                                       testleaf2 "baz";
                                     }
                                     unique_test {
                                       testkey "foo2";
                                       testleaf "bar";
                                       testleaf2 "baz";
                                     }
   ]]))
   assert(not success)

   -- Test unique validation (should succeed)
   checker(data.load_config_for_schema(unique_schema,
                                       mem.open_input_string [[
                                          unique_test {
                                            testkey "foo";
                                            testleaf "bar";
                                            testleaf2 "baz";
                                          }
                                          unique_test {
                                            testkey "foo2";
                                            testleaf "bar2";
                                            testleaf2 "baz";
                                          }
   ]]))

   -- Test min-elements and max-elements restrictions:
   local minmax_schema = schema.load_schema([[module minmax-schema {
      namespace "urn:ietf:params:xml:ns:yang:minmax-schema";
      prefix "test";

      list minmax_list_test {
        key "testkey"; min-elements 1; max-elements 2;
        leaf testkey { type string; mandatory true; }
        leaf testleaf { type string; mandatory true; }
      }

      leaf-list minmax_leaflist_test {
        type string; min-elements 1; max-elements 3;
      }
   }]])
   local checker = consistency_checker_from_schema(minmax_schema, true)

   -- Test minmax validation (should fail)
   local success, result = pcall(
      checker,
      data.load_config_for_schema(minmax_schema,
                                  mem.open_input_string [[
                                     minmax_leaflist_test "baz";
   ]]))
   assert(not success)
   print(result)

   -- Test minmax validation (should fail)
   local success, result = pcall(
      checker,
      data.load_config_for_schema(minmax_schema,
                                  mem.open_input_string [[
                                     minmax_list_test {
                                       testkey "foo";
                                       testleaf "bar";
                                     }
   ]]))
   assert(not success)
   print(result)

   -- Test minmax validation (should succeed)
   checker(data.load_config_for_schema(minmax_schema,
                                       mem.open_input_string [[
                                     minmax_list_test {
                                       testkey "foo";
                                       testleaf "bar";
                                     }
                                     minmax_leaflist_test "baz";
   ]]))

   -- Test minmax validation (should succeed)
   checker(data.load_config_for_schema(minmax_schema,
                                       mem.open_input_string [[
                                     minmax_list_test {
                                       testkey "foo";
                                       testleaf "bar";
                                     }
                                     minmax_list_test {
                                       testkey "foo2";
                                       testleaf "bar";
                                     }
                                     minmax_leaflist_test "baz";
   ]]))

   -- Test minmax validation (should succeed)
   checker(data.load_config_for_schema(minmax_schema,
                                       mem.open_input_string [[
                                     minmax_list_test {
                                       testkey "foo";
                                       testleaf "bar";
                                     }
                                     minmax_leaflist_test "baz";
                                     minmax_leaflist_test "baz";
                                     minmax_leaflist_test "baz";
   ]]))

   -- Test minmax validation (should fail)
   local success, result = pcall(
      checker,
      data.load_config_for_schema(minmax_schema,
                                  mem.open_input_string [[
                                     minmax_list_test {
                                       testkey "foo";
                                       testleaf "bar";
                                     }
                                     minmax_list_test {
                                       testkey "foo2";
                                       testleaf "bar";
                                     }
                                     minmax_list_test {
                                       testkey "foo3";
                                       testleaf "bar";
                                     }
                                     minmax_leaflist_test "baz";
   ]]))
   assert(not success)
   print(result)

   -- Test minmax validation (should fail)
   local success, result = pcall(
      checker,
      data.load_config_for_schema(minmax_schema,
                                  mem.open_input_string [[
                                     minmax_list_test {
                                       testkey "foo";
                                       testleaf "bar";
                                     }
                                     minmax_leaflist_test "baz";
                                     minmax_leaflist_test "baz";
                                     minmax_leaflist_test "baz";
                                     minmax_leaflist_test "baz";
   ]]))
   assert(not success)
   print(result)

   -- Test unique restrictions in choice body:
   local choice_unique_schema = schema.load_schema([[module choice-unique-schema {
      namespace "urn:ietf:params:xml:ns:yang:choice-unique-schema";
      prefix "test";

      choice ab {
         list unique_test {
           key "testkey"; unique "testleaf testleaf2";
           leaf testkey { type string; mandatory true; }
           leaf testleaf { type string; mandatory true; }
           leaf testleaf2 { type string; mandatory true; }
         }
         list duplicate_test {
           key "testkey";
           leaf testkey { type string; mandatory true; }
           leaf testleaf { type string;}
           leaf testleaf2 { type string;}
         }
      }
   }]])
   local checker = consistency_checker_from_schema(choice_unique_schema, true)

   -- Test unique validation in choice body (should fail)
   local success, result = pcall(
      checker,
      data.load_config_for_schema(choice_unique_schema,
                                  mem.open_input_string [[
                                     unique_test {
                                       testkey "foo";
                                       testleaf "bar";
                                       testleaf2 "baz";
                                     }
                                     unique_test {
                                       testkey "foo2";
                                       testleaf "bar";
                                       testleaf2 "baz";
                                     }
   ]]))
   assert(not success)

   -- Test unique validation in choice body (should succeed)
   checker(data.load_config_for_schema(choice_unique_schema,
                                       mem.open_input_string [[
                                          unique_test {
                                            testkey "foo";
                                            testleaf "bar";
                                            testleaf2 "baz";
                                          }
                                          unique_test {
                                            testkey "foo2";
                                            testleaf "bar2";
                                            testleaf2 "baz";
                                          }
   ]]))

   -- Test unique validation in choice body (should succeed)
   checker(data.load_config_for_schema(choice_unique_schema,
                                       mem.open_input_string [[
                                          duplicate_test {
                                            testkey "foo";
                                            testleaf "bar";
                                          }
                                          duplicate_test {
                                            testkey "foo2";
                                            testleaf "bar";
                                          }
   ]]))

   print("selftest: ok")
end
