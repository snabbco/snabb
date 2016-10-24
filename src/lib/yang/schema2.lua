-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
-- This module implements the schema tree and validation for YANG. It represents
-- the YANG statements with lua tables and provides a fast but flexible way to
-- represent and validate statements.
-- 
-- Since YANG statements are encapsulated in modules at the highest level one
-- should take their pre-parsed YANG document containing the module and load it
-- into the Module table.
module(..., package.seeall)
local parser = require("lib.yang.parser")

local ffi = require("ffi")
ffi.cdef("long long atoll(const char *nptr);")
local function tointeger(str)
   local i = ffi.C.atoll(str)
   if tostring(i) == str.."LL" then
      if i == tonumber(i) then return tonumber(i) else return i end
   end
end

local function error_with_path(path, msg, ...)
   error(string.format("%s: "..msg, path, ...))
end
local function assert_with_path(expr, path, msg, ...)
   if not expr then error_with_path(path, msg, ...) end
   return expr
end

-- (kind -> (function(Node) -> value))
local initializers = {}
local function declare_initializer(init, ...)
   for _, keyword in ipairs({...}) do initializers[keyword] = init end
end
   
local Node = {}
local function parse_node(src, parent_path, order)
   local ret = {}
   ret.kind = assert(src.keyword, 'missing keyword')
   if parent_path then
      ret.path = parent_path..'.'..ret.kind
   else
      ret.path = ret.kind
   end
   ret.order = order
   ret.argument_string = src.argument
   ret.children = parse_children(src, ret.path)
   ret = setmetatable(ret, {__index=Node})
   local initialize = initializers[ret.kind]
   if initialize then initialize(ret) end
   return ret
end

function parse_children(src, parent_path)
   local ret = {}
   for i, statement in ipairs(src.statements or {}) do
      local child = parse_node(statement, parent_path, i)
      if not ret[child.kind] then ret[child.kind] = {} end
      table.insert(ret[child.kind], child)
   end
   return ret
end

local function require_argument(node)
   return assert_with_path(node.argument_string, node.path,
                           'missing argument')
end

local function parse_range(node, range)
   local function parse_part(part)
      local l, r = part:match("^%s*([^%.]*)%s*%.%.%s*([^%s]*)%s*$")
      assert_with_path(l, node.path, 'bad range component: %s', part)
      if l ~= 'min' then
         l = assert_with_path(tointeger(l), node.path, "bad integer: %s", l)
      end
      if r ~= 'max' then
         r = assert_with_path(tointeger(r), node.path, "bad integer: %s", r)
      end
      return { l, r }
   end
   local parts = range:split("|")
   local res = {'or'}
   for part in range:split("|") do table.insert(res, parse_part(part)) end
   if #res == 1 then error_with_path(node.path, "empty range", range)
   elseif #res == 2 then return res[2]
   else return res end
end

local function collect_children(node, kinds)
   if type(kinds) == 'string' then return collect_children(node, {kinds}) end
   local ret = {}
   for _, kind in ipairs(kinds) do
      if node.children[kind] then
         for _, child in pairs(node.children[kind]) do
            table.insert(ret, child)
         end
      end
   end
   return ret
end

local function collect_children_by_prop(node, kinds, prop)
   local ret = {}
   for _, child in ipairs(collect_children(node, kinds)) do
      assert_with_path(child[prop], node.path,
                       'child of kind %s missing prop %s', child.kind, prop)
      assert_with_path(not ret[child[prop]], node.path,
                       'duplicate %s: %s', prop, child[prop])
      ret[child[prop]] = child
   end
   return ret
end

local function collect_children_by_id(node, kinds)
   return collect_children_by_prop(node, kinds, 'id')
end

local function collect_body_children(node)
   return collect_children_by_id(
      node,
      {'extension', 'feature', 'identity', 'typedef', 'grouping',
       'container', 'leaf', 'list', 'leaf-list', 'uses', 'choice',
       'anyxml', 'rpc', 'notification', 'deviation'})
end

local function collect_data_children(node)
   return collect_children_by_id(
      node,
      {'container', 'leaf', 'list', 'leaf-list', 'uses', 'choice', 'anyxml'})
end

local function at_least_one(tab)
   for k, v in pairs(tab) do return true end
   return false
end

local function collect_data_children_at_least_1(node)
   local ret = collect_data_children(node)
   if not at_least_one(ret) then
      error_with_path(node.path, "missing data statements")
   end
   return ret
end

local function collect_data_or_case_children_at_least_1(node)
   local ret = collect_children_by_id(
      node,
      {'container', 'leaf', 'list', 'leaf-list', 'uses', 'choice',
       'anyxml', 'case'})
   if not at_least_one(ret) then
      error_with_path(node.path, "missing data statements")
   end
   return ret
end

local function collect_child_properties(node, kind, field)
   local ret = {}
   for _, child in ipairs(collect_children(node, kind)) do
      table.insert(ret, child[field])
   end
   return ret
end

local function maybe_child(node, kind)
   local children = collect_children(node, kind)
   if #children > 1 then
      error_with_path(node.path, 'expected at most one child of type %s', kind)
   end
   return children[1]
end

local function maybe_child_property(node, kind, prop)
   local child = maybe_child(node, kind)
   if child then return child[prop] end
end

local function require_child(node, kind)
   local child = maybe_child(node, kind)
   if child then return child end
   error_with_path(node.path, 'missing child of type %s', kind)
end

local function require_child_property(node, kind, prop)
   return require_child(node, kind)[prop]
end

-- Simple statement kinds with string, natural, or boolean values all
-- just initialize by parsing their argument and storing it as the
-- "value" property in the schema node.
local function init_string(node)
   node.value = require_argument(node)
end
local function init_natural(node)
   local arg = require_argument(node)
   local as_num = tonumber(arg)
   assert_with_path(as_num and math.floor(as_num) == as_num and as_num >= 0,
                    node.path, 'not a natural number: %s', arg)
   node.value = as_num
end
local function init_boolean(node)
   local arg = require_argument(node)
   if arg == 'true' then node.value = true
   elseif arg == 'false' then node.value = false
   else error_with_path(node.path, 'not a valid boolean: %s', arg) end
end

-- For all other statement kinds, we have custom initializers that
-- parse out relevant sub-components and store them as named
-- properties on the schema node.
local function init_anyxml(node)
   node.id = require_argument(node)
   node.when = maybe_child_property(node, 'when', 'value')
   node.if_feature = collect_child_properties(node, 'if-feature', 'value')
   node.must = collect_child_properties(node, 'must', 'value')
   node.config = maybe_child_property(node, 'config', 'value')
   node.mandatory = maybe_child_property(node, 'mandatory', 'value')
   node.status = maybe_child_property(node, 'status', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
end
local function init_argument(node)
   node.id = require_argument(node)
   node.yin_element = maybe_child_property(node, 'yin-element', 'value')
end
local function init_augment(node)
   node.node_id = require_argument(node)
   node.when = maybe_child_property(node, 'when', 'value')
   node.if_feature = collect_child_properties(node, 'if-feature', 'value')
   node.status = maybe_child_property(node, 'status', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
   node.data = collect_data_or_case_children_at_least_1(node)
end
local function init_belongs_to(node)
   node.id = require_argument(node)
   node.prefix = require_child(node, 'prefix').value
end
local function init_case(node)
   node.id = require_argument(node)
   node.when = maybe_child_property(node, 'when', 'value')
   node.if_feature = collect_child_properties(node, 'if-feature', 'value')
   node.status = maybe_child_property(node, 'status', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
   node.data = collect_data_children(node)
end
local function init_choice(node)
   node.id = require_argument(node)
   node.when = maybe_child_property(node, 'when', 'value')
   node.if_feature = collect_child_properties(node, 'if-feature', 'value')
   node.default = maybe_child_property(node, 'default', 'value')
   node.config = maybe_child_property(node, 'config', 'value')
   node.mandatory = maybe_child_property(node, 'mandatory', 'value')
   node.status = maybe_child_property(node, 'status', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
   node.typedefs = collect_children_by_id(node, 'typedef')
   node.groupings = collect_children_by_id(node, 'grouping')
   node.data = collect_children_by_id(
      node,
      {'container', 'leaf', 'leaf-list', 'list', 'anyxml', 'case'})
end
local function init_container(node)
   node.id = require_argument(node)
   node.when = maybe_child_property(node, 'when', 'value')
   node.if_feature = collect_child_properties(node, 'if-feature', 'value')
   node.must = collect_child_properties(node, 'must', 'value')
   node.presence = maybe_child_property(node, 'presence', 'value')
   node.config = maybe_child_property(node, 'config', 'value')
   node.status = maybe_child_property(node, 'status', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
   node.typedefs = collect_children_by_id(node, 'typedef')
   node.groupings = collect_children_by_id(node, 'grouping')
   node.data = collect_data_children(node)
end
local function init_extension(node)
   node.id = require_argument(node)
   node.argument = maybe_child_property(node, 'argument', 'id')
   node.status = maybe_child_property(node, 'status', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
end
local function init_feature(node)
   node.id = require_argument(node)
   node.if_feature = collect_child_properties(node, 'if-feature', 'value')
   node.status = maybe_child_property(node, 'status', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
end
local function init_grouping(node)
   node.id = require_argument(node)
   node.status = maybe_child_property(node, 'status', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
   node.typedefs = collect_children_by_id(node, 'typedef')
   node.groupings = collect_children_by_id(node, 'grouping')
   node.data = collect_data_children(node)
end
local function init_identity(node)
   node.id = require_argument(node)
   node.base = maybe_child_property(node, 'base', 'id')
   node.status = maybe_child_property(node, 'status', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
end
local function init_import(node)
   node.id = require_argument(node)
   node.prefix = require_child_property(node, 'prefix', 'value')
end
local function init_include(node)
   node.id = require_argument(node)
   node.revision_date = maybe_child_property(node, 'revision-date', 'value')
end
local function init_input(node)
   node.typedefs = collect_children_by_id(node, 'typedef')
   node.groupings = collect_children_by_id(node, 'grouping')
   node.data = collect_data_children_at_least_1(node)
end
local function init_leaf(node)
   node.id = require_argument(node)
   node.when = maybe_child_property(node, 'when', 'value')
   node.if_feature = collect_child_properties(node, 'if-feature', 'value')
   node.type = require_child(node, 'type')
   node.units = maybe_child_property(node, 'units', 'value')
   node.must = collect_child_properties(node, 'must', 'value')
   node.default = maybe_child_property(node, 'default', 'value')
   node.config = maybe_child_property(node, 'config', 'value')
   node.mandatory = maybe_child_property(node, 'mandatory', 'value')
   node.status = maybe_child_property(node, 'status', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
end
local function init_leaf_list(node)
   node.id = require_argument(node)
   node.when = maybe_child_property(node, 'when', 'value')
   node.if_feature = collect_child_properties(node, 'if-feature', 'value')
   node.type = require_child(node, 'type')
   node.units = maybe_child_property(node, 'units', 'value')
   node.must = collect_child_properties(node, 'must', 'value')
   node.config = maybe_child_property(node, 'config', 'value')
   node.min_elements = maybe_child_property(node, 'min-elements', 'value')
   node.max_elements = maybe_child_property(node, 'max-elements', 'value')
   node.ordered_by = maybe_child_property(node, 'ordered-by', 'value')
   node.status = maybe_child_property(node, 'status', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
end
local function init_length(node)
   -- TODO: parse length arg str
   node.value = require_argument(node)
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
end
local function init_list(node)
   node.id = require_argument(node)
   node.when = maybe_child_property(node, 'when', 'value')
   node.if_feature = collect_child_properties(node, 'if-feature', 'value')
   node.must = collect_child_properties(node, 'must', 'value')
   node.key = maybe_child_property(node, 'key', 'value')
   node.unique = collect_child_properties(node, 'unique', 'value')
   node.config = maybe_child_property(node, 'config', 'value')
   node.min_elements = maybe_child_property(node, 'min-elements', 'value')
   node.max_elements = maybe_child_property(node, 'max-elements', 'value')
   node.ordered_by = maybe_child_property(node, 'ordered-by', 'value')
   node.status = maybe_child_property(node, 'status', 'value')
   node.typedefs = collect_children_by_id(node, 'typedef')
   node.groupings = collect_children_by_id(node, 'grouping')
   node.data = collect_data_children_at_least_1(node)
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
end
local function init_module(node)
   node.id = require_argument(node)
   node.yang_version = maybe_child_property(node, 'yang-version', 'value')
   node.namespace = require_child_property(node, 'namespace', 'value')
   node.prefix = require_child_property(node, 'prefix', 'value')
   node.imports = collect_children_by_id(node, 'import')
   node.includes = collect_children(node, 'include')
   node.organization = maybe_child_property(node, 'organization', 'value')
   node.contact = maybe_child_property(node, 'contact', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
   node.revisions = collect_children(node, 'revision')
   node.augments = collect_children(node, 'augment')
   node.body = collect_body_children(node)
end
local function init_namespace(node)
   -- TODO: parse uri?
   node.value = require_argument(node)
end
local function init_notification(node)
   node.id = require_argument(node)
   node.if_feature = collect_child_properties(node, 'if-feature', 'value')
   node.status = maybe_child_property(node, 'status', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
   node.typedefs = collect_children_by_id(node, 'typedef')
   node.groupings = collect_children_by_id(node, 'grouping')
   node.data = collect_data_children(node)
end
local function init_output(node)
   node.typedefs = collect_children_by_id(node, 'typedef')
   node.groupings = collect_children_by_id(node, 'grouping')
   node.data = collect_data_children_at_least_1(node)
end
local function init_path(node)
   -- TODO: parse path string
   node.value = require_argument(node)
end
local function init_pattern(node)
   node.value = require_argument(node)
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
end
local function init_range(node)
   -- TODO: parse range string
   node.value = parse_range(node, require_argument(node))
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
end
local function init_refine(node)
   node.node_id = require_argument(node)
   -- All subnode kinds.
   node.must = collect_child_properties(node, 'must', 'value')
   node.config = maybe_child_property(node, 'config', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
   -- Containers.
   node.presence = maybe_child_property(node, 'presence', 'value')
   -- Leaves, choice, and (for mandatory) anyxml.
   node.default = maybe_child_property(node, 'default', 'value')
   node.mandatory = maybe_child_property(node, 'mandatory', 'value')
   -- Leaf lists and lists.
   node.min_elements = maybe_child_property(node, 'min-elements', 'value')
   node.max_elements = maybe_child_property(node, 'max-elements', 'value')
end
local function init_revision(node)
   -- TODO: parse date
   node.value = require_argument(node)
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
end
local function init_rpc(node)
   node.id = require_argument(node)
   node.if_feature = collect_child_properties(node, 'if-feature', 'value')
   node.status = maybe_child_property(node, 'status', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
   node.typedefs = collect_children_by_id(node, 'typedef')
   node.groupings = collect_children_by_id(node, 'grouping')
   node.input = maybe_child(node, 'input')
   node.output = maybe_child(node, 'output')
end
local function init_type(node)
   node.id = require_argument(node)
   node.range = maybe_child(node, 'range')
   node.fraction_digits = maybe_child_property(node, 'fraction-digits', 'value')
   node.length = maybe_child_property(node, 'length', 'value')
   node.patterns = collect_children(node, 'pattern')
   node.enums = collect_children(node, 'enum')
   -- !!! path
   node.leafref = maybe_child_property(node, 'path', 'value')
   node.require_instances = collect_children(node, 'require-instance')
   node.identityref = maybe_child_property(node, 'base', 'value')
   node.union = collect_children(node, 'type')
   node.bits = collect_children(node, 'bit')
end
local function init_submodule(node)
   node.id = require_argument(node)
   node.yang_version = maybe_child_property(node, 'yang-version', 'value')
   node.belongs_to = require_child(node, 'belongs-to')
   node.imports = collect_children_by_id(node, 'import')
   node.includes = collect_children_by_id(node, 'include')
   node.organization = maybe_child_property(node, 'organization', 'value')
   node.contact = maybe_child_property(node, 'contact', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
   node.revisions = collect_children(node, 'revision')
   node.augments = collect_children(node, 'augment')
   node.body = collect_body_children(node)
end
local function init_typedef(node)
   node.id = require_argument(node)
   node.type = require_child(node, 'type')
   node.units = maybe_child_property(node, 'units', 'value')
   node.default = maybe_child_property(node, 'default', 'value')
   node.status = maybe_child_property(node, 'status', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
end
local function init_uses(node)
   node.id = require_argument(node)
   node.when = maybe_child_property(node, 'when', 'value')
   node.if_feature = collect_child_properties(node, 'if-feature', 'value')
   node.status = maybe_child_property(node, 'status', 'value')
   node.description = maybe_child_property(node, 'description', 'value')
   node.reference = maybe_child_property(node, 'reference', 'value')
   node.typedefs = collect_children_by_id(node, 'typedef')
   node.refines = collect_children(node, 'refine')
   node.augments = collect_children(node, 'augment')
end
local function init_value(node)
   local arg = require_argument(node)
   local as_num = tonumber(arg)
   assert_with_path(as_num and math.floor(as_num) == as_num,
                    node.path, 'not an integer: %s', arg)
   node.value = as_num
end

declare_initializer(
   init_string, 'prefix', 'organization', 'contact', 'description',
   'reference', 'units',  'revision-date', 'base','if-feature',
   'default', 'enum', 'bit', 'status', 'presence', 'ordered-by', 'must',
   'error-message', 'error-app-tag', 'max-value', 'key', 'unique', 'when',
   'deviation', 'deviate')
declare_initializer(
   init_natural, 'yang-version', 'fraction-digits', 'position',
   'min-elements', 'max-elements')
declare_initializer(
   init_boolean, 'config', 'mandatory', 'require-instance', 'yin-element')
declare_initializer(init_anyxml, 'anyxml')
declare_initializer(init_argument, 'argument')
declare_initializer(init_augment, 'augment')
declare_initializer(init_belongs_to, 'belongs-to')
declare_initializer(init_case, 'case')
declare_initializer(init_choice, 'choice')
declare_initializer(init_container, 'container')
declare_initializer(init_extension, 'extension')
declare_initializer(init_feature, 'feature')
declare_initializer(init_grouping, 'grouping')
declare_initializer(init_identity, 'identity')
declare_initializer(init_import, 'import')
declare_initializer(init_include, 'include')
declare_initializer(init_input, 'input')
declare_initializer(init_leaf, 'leaf')
declare_initializer(init_leaf_list, 'leaf-list')
declare_initializer(init_length, 'length')
declare_initializer(init_list, 'list')
declare_initializer(init_module, 'module')
declare_initializer(init_namespace, 'namespace')
declare_initializer(init_notification, 'notification')
declare_initializer(init_output, 'output')
declare_initializer(init_path, 'path')
declare_initializer(init_pattern, 'pattern')
declare_initializer(init_range, 'range')
declare_initializer(init_refine, 'refine')
declare_initializer(init_revision, 'revision')
declare_initializer(init_rpc, 'rpc')
declare_initializer(init_submodule, 'submodule')
declare_initializer(init_type, 'type')
declare_initializer(init_typedef, 'typedef')
declare_initializer(init_uses, 'uses')
declare_initializer(init_value, 'value')

local function schema_from_ast(ast)
   assert(#ast == 1, 'expected a single module form')
   local parsed = parse_node(ast[1])
   assert(parsed.kind == 'module', 'not a yang module')
   return parsed
end

function parse_schema(src, filename)
   return schema_from_ast(parser.parse_string(src, filename))
end

function parse_schema_file(filename)
   return schema_from_ast(parser.parse_file(filename))
end

function selftest()
   local test_schema = [[module fruit {
      namespace "urn:testing:fruit";
      prefix "fruit";

      import ietf-inet-types {prefix inet; }
      import ietf-yang-types {prefix yang; }

      organization "Fruit Inc.";

      contact "John Smith fake@person.tld";

      description "Module to test YANG schema lib";

      revision 2016-05-27 {
         description "Revision 1";
         reference "tbc";
      }

      revision 2016-05-28 {
         description "Revision 2";
         reference "tbc";
      }

      feature bowl {
         description "A fruit bowl";
         reference "fruit-bowl";
      }

      grouping fruit {
         description "Represets a piece of fruit";

         leaf name {
            type string;
            mandatory true;
            description "Name of fruit.";
         }

         leaf score {
            type uint8 {
               range 0..10;
            }
            mandatory true;
            description "How nice is it out of 10";
         }

         leaf tree-grown {
            type boolean;
            description "Is it grown on a tree?";
         }
      }

      container fruit-bowl {
         description "Represents a fruit bowl";

         leaf description {
            type string;
            description "About the bowl";
         }

         list contents {
            uses fruit;
         }
      }
   }]]

  -- Convert the schema using the already tested parser.
  local schema = parse_schema(test_schema, "schema selftest")

  assert(schema.id == "fruit")
  assert(schema.namespace == "urn:testing:fruit")
  assert(schema.prefix == "fruit")
  assert(schema.contact == "John Smith fake@person.tld")
  assert(schema.organization == "Fruit Inc.")
  assert(schema.description == "Module to test YANG schema lib")

  -- Check both modules exist. (Also need to check they've loaded)
  assert(schema.imports["ietf-inet-types"])
  assert(schema.imports["ietf-yang-types"])

  -- Check all revisions are accounted for.
  assert(schema.revisions[1].description == "Revision 1")
  assert(schema.revisions[1].value == "2016-05-27")
  assert(schema.revisions[2].description == "Revision 2")
  assert(schema.revisions[2].value == "2016-05-28")

  -- Check that the feature statements are there.
  assert(schema.body["bowl"])
  assert(schema.body["bowl"].kind == 'feature')

  -- Check the groupings
  assert(schema.body["fruit"])
  assert(schema.body["fruit"].description)
  assert(schema.body["fruit"].data["name"])
  assert(schema.body["fruit"].data["name"].kind == "leaf")
  assert(schema.body["fruit"].data["name"].type.id == "string")
  assert(schema.body["fruit"].data["name"].mandatory == true)
  assert(schema.body["fruit"].data["name"].description == "Name of fruit.")
  assert(schema.body["fruit"].data["score"].type.id == "uint8")
  assert(schema.body["fruit"].data["score"].mandatory == true)
  assert(schema.body["fruit"].data["score"].type.range.value[1] == 0)
  assert(schema.body["fruit"].data["score"].type.range.value[2] == 10)

  -- Check the containers description (NOT the leaf called "description")
  assert(schema.body["fruit-bowl"].description == "Represents a fruit bowl")

  -- Check the container has a leaf called "description"
  local desc = schema.body["fruit-bowl"].data['description']
  assert(desc.type.id == "string")
  assert(desc.description == "About the bowl")

  parse_schema(require('lib.yang.example_yang'))
end
