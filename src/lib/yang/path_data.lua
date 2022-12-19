-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local ffi = require("ffi")
local data = require("lib.yang.data")
local value = require("lib.yang.value")
local schema = require("lib.yang.schema")
local path = require("lib.yang.path")
local parse_path = path.parse_path
local unparse_path = path.unparse_path
local parse_relative_path = path.parse_relative_path
local normalize_path = path.normalize_path
local util = require("lib.yang.util")
local list = require("lib.yang.list")
local normalize_id = data.normalize_id
local lib = require("core.lib")

local function compute_struct_getter(name, getter)
   local id = normalize_id(name)
   return function (data)
      local struct = getter(data)
      if struct[id] ~= nil then
         return struct[id]
      else
         error("Container has no member '"..name.."'")
      end
   end
end

local function compute_array_getter(idx, getter)
   return function (data)
      local array = getter(data)
      if idx > #array then
         error("Index "..idx.." is out of bounds")
      end
      return array[idx]
   end
end

local function compute_list_getter(key, getter)
   return function (data)
      local l = list.object(getter(data))
      local entry = l:find_entry(key)
      if entry ~= nil then
         return entry
      else
         error("List has no such entry")
      end
   end
end

local function compute_getter(grammar, part, getter)
   if grammar.type == 'struct' or grammar.type == 'sequence' then
      getter = compute_struct_getter(part.name, getter)
      grammar = part.grammar
   else
      error("Invalid path: '"..part.name.."' is not a container")
   end
   if part.key then
      if grammar.type == 'array' then
         getter = compute_array_getter(part.key, getter)
         -- Pretend that array elements are scalars.
         grammar = {type="scalar", argument_type=grammar.element_type,
                    ctype=grammar.ctype}
      elseif grammar.type == 'list' then
         getter = compute_list_getter(part.key, getter)
         -- Pretend that list entries are structs.
         grammar = {type="struct", members=grammar.values,
                    ctype=grammar.value_ctype}
      else
         error("Invalid path: '"..name.."' can not be queried")
      end
   end
   return getter, grammar
end

-- Returns a resolver for a particular schema and *lua* path.
function resolver(grammar, path)
   path = parse_path(path, grammar)
   local getter = function(data) return data end
   for _, part in ipairs(path) do
      getter, grammar = compute_getter(grammar, part, getter)
   end
   return getter, grammar
end

resolver = util.memoize(resolver)

local function grammar_for_schema(schema, path, is_config)
   local grammar = data.data_grammar_from_schema(schema, is_config ~= false)
   local path = parse_path(path or '/', grammar)
   if #path > 0 then
      return path[#path].grammar
   else
      return grammar
   end
end

function grammar_for_schema_by_name(schema_name, path, is_config)
   local schema = schema.load_schema_by_name(schema_name)
   return grammar_for_schema(schema, path, is_config)
end

grammar_for_schema_by_name = util.memoize(grammar_for_schema_by_name)

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
   local head = parse_path(path, grammar)
   local tail = table.remove(head)
   local tail_name, tail_key = tail.name, tail.key
   local target = head[#head]
   local target_name, target_key = target.name, target.key
   if tail_key then
      -- The path ends in a query; it must denote an array or
      -- list item.
      table.insert(head, {name=tail_name, query={}})
      local getter, grammar = resolver(grammar, head)
      if grammar.type == 'array' then
         local idx = tail_key
         return function(config, subconfig)
            local array = getter(config)
            array[idx] = subconfig
            return config
         end
      elseif grammar.type == 'list' then
         return function (config, subconfig)
            local l = list.object(getter(config))
            l:add_or_update_entry(tail_key, subconfig)
            return config
         end
      else
         error("Invalid path: '"..tail_name.."' can not be queried")
      end
   elseif target_key then
      -- The path updates an entry in a collection; it must denote
      -- a list item.
      head[#head] = {name=target_name, query={}}
      local getter, grammar = resolver(grammar, head)
      local tail_id = data.normalize_id(tail_name)
      assert(grammar.type == 'list')
      return function (config, subconfig)
         local l = list.object(getter(config))
         local entry = l:find_entry(target_key)
         entry[tail_id] = subconfig
         l:add_or_update_entry(entry)
         return config
      end
   else
      -- No query; the simple case.
      local getter, grammar = resolver(grammar, head)
      if grammar.type ~= 'struct' then
         error("Invalid path: missing query for '"..tail.name.."'")
      end
      local tail_id = data.normalize_id(tail_name)
      return function(config, subconfig)
         getter(config)[tail_id] = subconfig
         return config
      end
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
               error("Can not add already-existing list entry #"..i)
            end
         end
         for _, entry in ipairs(subconfig) do
            l:add_entry(entry)
         end
         return config
      end
   else
      error("Invalid path: '"..tail_name.."' is not a list or a leaf-list")
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
   local head = parse_path(path, grammar)
   local tail = table.remove(head)
   if not tail.key then error("Invalid path: missing query") end
   local tail_name, key = tail.name, tail.key
   table.insert(head, {name=tail_name, query={}})
   local getter, grammar = resolver(grammar, head)
   if grammar.type == 'array' then
      local idx = key
      return function(config)
         local cur = getter(config)
         if idx > #cur then
            error("Leaf-list '"..tail_name"' has no element #"..idx)
         end
         cur[idx] = nil
         return config
      end
   elseif grammar.type == 'list' then
      return function(config)
         local l = list.object(getter(config))
         if not l:remove_entry(key) then
            error("List '"..tail_name"' has no entry matching the query")
         end
         return config
      end
   else
      error("Invalid path: '"..tail_name.."' is not a list or a leaf-list")
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

function checker_from_grammar(grammar, checker)
   local function path_add(path, name)
      local p = {}
      function p.unparse() return unparse_path(p, grammar) end
      for i, part in ipairs(path) do p[i] = part end
      p[#p+1] = {name=name, query={}}
      return p
   end
   local function visitor(node, path)
      local check = checker(node, path, grammar)
      if node.type == 'scalar' then
         return check
      elseif node.type == 'struct' then
         local visits = {}
         for name, member in expanded_pairs(node.members) do
            local id = normalize_id(name)
            visits[id] = visitor(member, path_add(path, name))
         end
         for _ in pairs(visits) do
            return function (data, root)
               root = root or data
               if check then check(data, root) end
               for id, visit in pairs(visits) do
                  if data[id] then visit(data[id], root) end
               end
            end
         end
         return check
      elseif node.type == 'array' then
         -- Pretend that array elements are scalars.
         local pseudo_node = {type="scalar", argument_type=node.element_type,
                              ctype=node.ctype}
         local check_elt = checker(pseudo_node, path, grammar)
         if check_elt then
            return function (data, root)
               root = root or data
               if check then check(data, root) end
               for idx, elt in ipairs(data) do
                  path[#path].key = idx
                  check_elt(elt, root)
               end
               path[#path].key = nil
            end
         end
         return check
      elseif node.type == 'list' then
         local checks_and_visits = {}
         for name, member in pairs(node.keys) do
            local id = normalize_id(name)
            checks_and_visits[id] =
               checker(member, path_add(path, name), grammar)
         end
         for name, member in expanded_pairs(node.values) do
            local id = normalize_id(name)
            checks_and_visits[id] =
               visitor(member, path_add(path, name))
         end
         for _ in pairs(checks_and_visits) do
            return function (data, root)
               root = root or data
               if check then check(data, root) end
               for _, entry in ipairs(data) do
                  path[#path].key = entry
                  for id, visit in pairs(checks_and_visits) do
                     if entry[id] then visit(entry[id], root) end
                  end
               end
               path[#path].key = nil
            end
         end
         return check
      else
         error("BUG: unhandled node type: "..node.type)
      end
   end
   return visitor(grammar, {})
end

local function consistency_error(path, msg, ...)
   if path.unparse then path = path.unparse() end
   error(("Consistency error in '%s': %s")
      :format(normalize_path(path), msg:format(...)))
end

local function leafref_checker(node, path, grammar)
   if node.type ~= 'scalar' then return end
   if not (node.argument_type and node.argument_type.leafref) then return end
   local ok, leafref = pcall(parse_path, node.argument_type.leafref)
   if not ok then
      consistency_error(path,
         "invalid leafref '%s' (%s)",
         node.argument_type.leafref, leafref)
   end
   for _, part in ipairs(leafref) do
      -- NYI: queries in leafrefs are currently ignored.
      part.query = {}
   end
   local ok, err = pcall(parse_relative_path, leafref, path, grammar)
   if not ok then
      consistency_error(path,
         "invalid leafref '%s' (%s)",
         node.argument_type.leafref, err)
   end
   if node.require_instances ~= false then
      -- We only support one simple case:
      -- leafrefs that are keys into lists with a single key.
      local leaf = table.remove(leafref)
      local list = leafref[#leafref]
      if not (list and list.grammar.type == 'list') then return end
      if not list.grammar.list.has_key then return end
      for k in pairs(list.grammar.keys) do
         if k ~= leaf.name then return end
      end
      return function (data, root)
         local ok, err = pcall(function ()
            list.query = {[leaf.name]=assert(data, "missing leafref value")}
            local p = parse_relative_path(leafref, unparse_path(path, grammar))
            return resolver(grammar, p)(root)
         end)
         if not ok then
            consistency_error(path,
               "broken leafref integrity for '%s' (%s)",
               normalize_path(leafref), err)
         end
      end
   end
end

local function uniqueness_checker(node, path)
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
   local function has_collision(list, collision)
      -- Sad quadratic loop
      for i, x in ipairs(list) do
         for j, y in ipairs(list) do
            if i == j then break end
            if collision(x, y) then
               return true
            end
         end
      end
   end
   if node.type ~= 'list' then return end
   if not node.unique or #node.unique == 0 then return end
   local invariants = {}
   for _, unique in ipairs(node.unique) do
      invariants[unique] = collision_checker(unique)
   end
   return function (data)
      for unique, collision in pairs(invariants) do
         if has_collision(data, collision) then
            consistency_error(path, "not unique (%s)", unique)
         end
      end
   end
end

local function minmax_checker(node, path)
   if not (node.type == 'array' or node.type == 'list') then return end
   if not (node.min_elements or node.max_elements) then return end
   return function (data)
      local n = #data
      if node.min_elements and n < node.min_elements then
         consistency_error(path,
            "requires at least %d element(s)", node.min_elements)
      end
      if node.max_elements and n > node.max_elements then
         consistency_error(path,
            "must not have more than %d element(s)", node.max_elements)
      end
   end
end

function consistency_checker_from_grammar(grammar)
   local checks = {
      checker_from_grammar(grammar, leafref_checker),
      checker_from_grammar(grammar, uniqueness_checker),
      checker_from_grammar(grammar, minmax_checker)
   }
   return function (data)
      for _, check in pairs(checks) do
         check(data)
      end
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

   local invalid_data = data.load_config_for_schema(my_schema, mem.open_input_string([[
   test {
      interface {
         name "eth1";
         admin-status true;
         address {
            ip 192.168.0.1;
         }
      }
      mgmt "eth0";
   }
   ]]))
   local ok, err = pcall(checker, invalid_data)
   assert(not ok)
   print(err)

   local checker = consistency_checker_from_schema_by_name('ietf-alarms', false)
   assert(checker)

   local scm = schema.load_schema_by_name('snabb-softwire-v3')
   local grammar = data.config_grammar_from_schema(scm)
   setter_for_grammar(grammar, "/softwire-config/instance[device=test]/"..
                               "queue[id=0]/external-interface/ip")
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
   print(result)

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

   -- Test restrictions embedded in list entries:
   local nested_schema = schema.load_schema([[module nested-schema {
      namespace "urn:ietf:params:xml:ns:yang:nested-schema";
      prefix "test";

      list entry {
         key name;
         leaf name { type string; }
         leaf-list ll { type string; min-elements 1; }
      }

      list ref {
         key name;
         leaf name { type string; }
         leaf entry {
            type leafref {
               path "../../entry/name";
            }
         }
      }
   }]])
   local checker = consistency_checker_from_schema(nested_schema, true)
   
   -- Test validation (should succeed)
   checker(data.load_config_for_schema(nested_schema,
                                       mem.open_input_string [[
      entry { name foo; ll "a"; }
      ref { name bar; entry foo; }
   ]]))

   -- Test minmax inconsistency in list entry (should fail)
   local ok, err = pcall(checker,
      data.load_config_for_schema(nested_schema,
                                  mem.open_input_string [[
      entry { name foo; }
      ref { name bar; entry foo; }
   ]]))
   assert(not ok)
   print(err)

   -- Test leafref inconsistency in list entry (should fail)
   local ok, err = pcall(checker,
      data.load_config_for_schema(nested_schema,
                                  mem.open_input_string [[
      entry { name foo; ll "a"; }
      ref { name bar; entry foo1; }
   ]]))
   assert(not ok)
   print(err)


   print("selftest: ok")
end
