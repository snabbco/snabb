-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local parser = require("lib.yang.parser")
local util = require("lib.yang.util")

local function error_with_loc(loc, msg, ...)
   error(string.format("%s: "..msg, loc, ...))
end
local function assert_with_loc(expr, loc, msg, ...)
   if not expr then error_with_loc(loc, msg, ...) end
   return expr
end

local function shallow_copy(node)
   local out = {}
   for k,v in pairs(node) do out[k] = v end
   return out
end

-- (kind -> (function(Node) -> value))
local initializers = {}
local function declare_initializer(init, ...)
   for _, keyword in ipairs({...}) do initializers[keyword] = init end
end

local function parse_node(src)
   local ret = {}
   ret.kind = assert(src.keyword, 'missing keyword')
   local children = parse_children(src)
   local initialize = initializers[ret.kind]
   if initialize then initialize(ret, src.loc, src.argument, children) end
   return ret
end

function parse_children(src)
   local ret = {}
   for i, statement in ipairs(src.statements or {}) do
      local child = parse_node(statement)
      if not ret[child.kind] then ret[child.kind] = {} end
      table.insert(ret[child.kind], child)
   end
   return ret
end

local function require_argument(loc, argument)
   return assert_with_loc(argument, loc, 'missing argument')
end

local function parse_range(loc, range)
   local function parse_part(part)
      local l, r = part:match("^%s*([^%.]*)%s*%.%.%s*([^%s]*)%s*$")
      assert_with_loc(l, loc, 'bad range component: %s', part)
      if l ~= 'min' then l = util.tointeger(l) end
      if r ~= 'max' then r = util.tointeger(r) end
      return { l, r }
   end
   local parts = range:split("|")
   local res = {'or'}
   for part in range:split("|") do table.insert(res, parse_part(part)) end
   if #res == 1 then error_with_loc(loc, "empty range", range)
   elseif #res == 2 then return res[2]
   else return res end
end

local function collect_children(children, kinds)
   if type(kinds) == 'string' then
      return collect_children(children, {kinds})
   end
   local ret = {}
   for _, kind in ipairs(kinds) do
      if children[kind] then
         for _, child in pairs(children[kind]) do
            table.insert(ret, child)
         end
      end
   end
   return ret
end

local function collect_children_by_prop(loc, children, kinds, prop)
   local ret = {}
   for _, child in ipairs(collect_children(children, kinds)) do
      assert_with_loc(child[prop], loc, 'child of kind %s missing prop %s',
                      child.kind, prop)
      assert_with_loc(not ret[child[prop]], loc, 'duplicate %s: %s',
                      prop, child[prop])
      ret[child[prop]] = child
   end
   return ret
end

local function collect_children_by_id(loc, children, kinds)
   return collect_children_by_prop(loc, children, kinds, 'id')
end

local function collect_body_children(loc, children)
   return collect_children_by_id(
      loc, children,
      {'container', 'leaf', 'list', 'leaf-list', 'uses', 'choice', 'anyxml'})
end

local function at_least_one(tab)
   for k, v in pairs(tab) do return true end
   return false
end

local function collect_body_children_at_least_1(loc, children)
   local ret = collect_body_children(loc, children)
   if not at_least_one(ret) then
      error_with_loc(loc, "missing data statements")
   end
   return ret
end

local function collect_data_or_case_children_at_least_1(loc, children)
   local ret = collect_children_by_id(
      loc, children,
      {'container', 'leaf', 'list', 'leaf-list', 'uses', 'choice',
       'anyxml', 'case'})
   if not at_least_one(ret) then
      error_with_loc(loc, "missing data statements")
   end
   return ret
end

local function collect_child_properties(children, kind, field)
   local ret = {}
   for _, child in ipairs(collect_children(children, kind)) do
      table.insert(ret, child[field])
   end
   return ret
end

local function maybe_child(loc, children, kind)
   local children = collect_children(children, kind)
   if #children > 1 then
      error_with_loc(loc, 'expected at most one child of type %s', kind)
   end
   return children[1]
end

local function maybe_child_property(loc, children, kind, prop)
   local child = maybe_child(loc, children, kind)
   if child then return child[prop] end
end

local function require_child(loc, children, kind)
   local child = maybe_child(loc, children, kind)
   if child then return child end
   error_with_loc(loc, 'missing child of type %s', kind)
end

local function require_child_property(loc, children, kind, prop)
   return require_child(loc, children, kind)[prop]
end

-- Simple statement kinds with string, natural, or boolean values all
-- just initialize by parsing their argument and storing it as the
-- "value" property in the schema node.
local function init_string(node, loc, argument, children)
   node.value = require_argument(loc, argument)
end
local function init_natural(node, loc, argument, children)
   local arg = require_argument(loc, argument)
   local as_num = tonumber(arg)
   assert_with_loc(as_num and math.floor(as_num) == as_num and as_num >= 0,
                   loc, 'not a natural number: %s', arg)
   node.value = as_num
end
local function init_boolean(node, loc, argument, children)
   local arg = require_argument(loc, argument)
   if arg == 'true' then node.value = true
   elseif arg == 'false' then node.value = false
   else error_with_loc(loc, 'not a valid boolean: %s', arg) end
end

-- For all other statement kinds, we have custom initializers that
-- parse out relevant sub-components and store them as named
-- properties on the schema node.
local function init_anyxml(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.when = maybe_child_property(loc, children, 'when', 'value')
   node.if_features = collect_child_properties(children, 'if-feature', 'value')
   node.must = collect_child_properties(children, 'must', 'value')
   node.config = maybe_child_property(loc, children, 'config', 'value')
   node.mandatory = maybe_child_property(loc, children, 'mandatory', 'value')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
end
local function init_argument(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.yin_element = maybe_child_property(loc, children, 'yin-element', 'value')
end
local function init_augment(node, loc, argument, children)
   node.node_id = require_argument(loc, argument)
   node.when = maybe_child_property(loc, children, 'when', 'value')
   node.if_features = collect_child_properties(children, 'if-feature', 'value')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
   node.body = collect_data_or_case_children_at_least_1(loc, children)
end
local function init_belongs_to(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.prefix = require_child(loc, children, 'prefix').value
end
local function init_case(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.when = maybe_child_property(loc, children, 'when', 'value')
   node.if_features = collect_child_properties(children, 'if-feature', 'value')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
   node.body = collect_body_children(loc, children)
end
local function init_choice(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.when = maybe_child_property(loc, children, 'when', 'value')
   node.if_features = collect_child_properties(children, 'if-feature', 'value')
   node.default = maybe_child_property(loc, children, 'default', 'value')
   node.config = maybe_child_property(loc, children, 'config', 'value')
   node.mandatory = maybe_child_property(loc, children, 'mandatory', 'value')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
   node.typedefs = collect_children_by_id(loc, children, 'typedef')
   node.groupings = collect_children_by_id(loc, children, 'grouping')
   node.body = collect_children_by_id(
      loc, children,
      {'container', 'leaf', 'leaf-list', 'list', 'anyxml', 'case'})
end
local function init_container(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.when = maybe_child_property(loc, children, 'when', 'value')
   node.if_features = collect_child_properties(children, 'if-feature', 'value')
   node.must = collect_child_properties(children, 'must', 'value')
   node.presence = maybe_child_property(loc, children, 'presence', 'value')
   node.config = maybe_child_property(loc, children, 'config', 'value')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
   node.typedefs = collect_children_by_id(loc, children, 'typedef')
   node.groupings = collect_children_by_id(loc, children, 'grouping')
   node.body = collect_body_children(loc, children)
end
local function init_extension(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.argument = maybe_child_property(loc, children, 'argument', 'id')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
end
local function init_feature(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.if_features = collect_child_properties(children, 'if-feature', 'value')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
end
local function init_grouping(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
   node.typedefs = collect_children_by_id(loc, children, 'typedef')
   node.groupings = collect_children_by_id(loc, children, 'grouping')
   node.body = collect_body_children(loc, children)
end
local function init_identity(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.base = maybe_child_property(loc, children, 'base', 'id')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
end
local function init_import(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.prefix = require_child_property(loc, children, 'prefix', 'value')
   node.revision_date = maybe_child_property(loc, children, 'revision-date', 'value')
end
local function init_include(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.revision_date = maybe_child_property(loc, children, 'revision-date', 'value')
end
local function init_input(node, loc, argument, children)
   node.typedefs = collect_children_by_id(loc, children, 'typedef')
   node.groupings = collect_children_by_id(loc, children, 'grouping')
   node.body = collect_body_children_at_least_1(loc, children)
end
local function init_leaf(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.when = maybe_child_property(loc, children, 'when', 'value')
   node.if_features = collect_child_properties(children, 'if-feature', 'value')
   node.type = require_child(loc, children, 'type')
   node.units = maybe_child_property(loc, children, 'units', 'value')
   node.must = collect_child_properties(children, 'must', 'value')
   node.default = maybe_child_property(loc, children, 'default', 'value')
   node.config = maybe_child_property(loc, children, 'config', 'value')
   node.mandatory = maybe_child_property(loc, children, 'mandatory', 'value')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
end
local function init_leaf_list(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.when = maybe_child_property(loc, children, 'when', 'value')
   node.if_features = collect_child_properties(children, 'if-feature', 'value')
   node.type = require_child(loc, children, 'type')
   node.units = maybe_child_property(loc, children, 'units', 'value')
   node.must = collect_child_properties(children, 'must', 'value')
   node.config = maybe_child_property(loc, children, 'config', 'value')
   node.min_elements = maybe_child_property(loc, children, 'min-elements', 'value')
   node.max_elements = maybe_child_property(loc, children, 'max-elements', 'value')
   node.ordered_by = maybe_child_property(loc, children, 'ordered-by', 'value')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
end
local function init_length(node, loc, argument, children)
   -- TODO: parse length arg str
   node.value = require_argument(loc, argument)
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
end
local function init_list(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.when = maybe_child_property(loc, children, 'when', 'value')
   node.if_features = collect_child_properties(children, 'if-feature', 'value')
   node.must = collect_child_properties(children, 'must', 'value')
   node.key = maybe_child_property(loc, children, 'key', 'value')
   node.unique = collect_child_properties(children, 'unique', 'value')
   node.config = maybe_child_property(loc, children, 'config', 'value')
   node.min_elements = maybe_child_property(loc, children, 'min-elements', 'value')
   node.max_elements = maybe_child_property(loc, children, 'max-elements', 'value')
   node.ordered_by = maybe_child_property(loc, children, 'ordered-by', 'value')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.typedefs = collect_children_by_id(loc, children, 'typedef')
   node.groupings = collect_children_by_id(loc, children, 'grouping')
   node.body = collect_body_children_at_least_1(loc, children)
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
end
local function init_module(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.yang_version = maybe_child_property(loc, children, 'yang-version', 'value')
   node.namespace = require_child_property(loc, children, 'namespace', 'value')
   node.prefix = require_child_property(loc, children, 'prefix', 'value')
   node.imports = collect_children_by_prop(loc, children, 'import', 'prefix')
   node.includes = collect_children_by_id(loc, children, 'include')
   node.organization = maybe_child_property(loc, children, 'organization', 'value')
   node.contact = maybe_child_property(loc, children, 'contact', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
   node.revisions = collect_children(children, 'revision')
   node.augments = collect_children(children, 'augment')
   node.typedefs = collect_children_by_id(loc, children, 'typedef')
   node.groupings = collect_children_by_id(loc, children, 'grouping')
   node.features = collect_children_by_id(loc, children, 'feature')
   node.extensions = collect_children_by_id(loc, children, 'extension')
   node.identities = collect_children_by_id(loc, children, 'identity')
   node.rpcs = collect_children_by_id(loc, children, 'rpc')
   node.notifications = collect_children_by_id(loc, children, 'notification')
   node.deviations = collect_children_by_id(loc, children, 'deviation')
   node.body = collect_body_children(loc, children)
end
local function init_namespace(node, loc, argument, children)
   -- TODO: parse uri?
   node.value = require_argument(loc, argument)
end
local function init_notification(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.if_features = collect_child_properties(children, 'if-feature', 'value')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
   node.typedefs = collect_children_by_id(loc, children, 'typedef')
   node.groupings = collect_children_by_id(loc, children, 'grouping')
   node.body = collect_body_children(loc, children)
end
local function init_output(node, loc, argument, children)
   node.typedefs = collect_children_by_id(loc, children, 'typedef')
   node.groupings = collect_children_by_id(loc, children, 'grouping')
   node.body = collect_body_children_at_least_1(loc, children)
end
local function init_path(node, loc, argument, children)
   -- TODO: parse path string
   node.value = require_argument(loc, argument)
end
local function init_pattern(node, loc, argument, children)
   node.value = require_argument(loc, argument)
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
end
local function init_range(node, loc, argument, children)
   node.value = parse_range(loc, require_argument(loc, argument))
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
end
local function init_refine(node, loc, argument, children)
   node.node_id = require_argument(loc, argument)
   -- All subnode kinds.
   node.must = collect_child_properties(children, 'must', 'value')
   node.config = maybe_child_property(loc, children, 'config', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
   -- Containers.
   node.presence = maybe_child_property(loc, children, 'presence', 'value')
   -- Leaves, choice, and (for mandatory) anyxml.
   node.default = maybe_child_property(loc, children, 'default', 'value')
   node.mandatory = maybe_child_property(loc, children, 'mandatory', 'value')
   -- Leaf lists and lists.
   node.min_elements = maybe_child_property(loc, children, 'min-elements', 'value')
   node.max_elements = maybe_child_property(loc, children, 'max-elements', 'value')
end
local function init_revision(node, loc, argument, children)
   -- TODO: parse date
   node.value = require_argument(loc, argument)
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
end
local function init_rpc(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.if_features = collect_child_properties(children, 'if-feature', 'value')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
   node.typedefs = collect_children_by_id(loc, children, 'typedef')
   node.groupings = collect_children_by_id(loc, children, 'grouping')
   node.input = maybe_child(loc, children, 'input')
   node.output = maybe_child(loc, children, 'output')
end
local function init_type(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.range = maybe_child(loc, children, 'range')
   node.fraction_digits = maybe_child_property(loc, children, 'fraction-digits', 'value')
   node.length = maybe_child_property(loc, children, 'length', 'value')
   node.patterns = collect_children(children, 'pattern')
   node.enums = collect_children(children, 'enum')
   -- !!! path
   node.leafref = maybe_child_property(loc, children, 'path', 'value')
   node.require_instances = collect_children(children, 'require-instance')
   node.identityref = maybe_child_property(loc, children, 'base', 'value')
   node.union = collect_children(children, 'type')
   node.bits = collect_children(children, 'bit')
end
local function init_submodule(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.yang_version = maybe_child_property(loc, children, 'yang-version', 'value')
   node.belongs_to = require_child(loc, children, 'belongs-to')
   node.imports = collect_children_by_id(loc, children, 'import')
   node.includes = collect_children_by_id(loc, children, 'include')
   node.organization = maybe_child_property(loc, children, 'organization', 'value')
   node.contact = maybe_child_property(loc, children, 'contact', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
   node.revisions = collect_children(children, 'revision')
   node.augments = collect_children(children, 'augment')
   node.typedefs = collect_children_by_id(loc, children, 'typedef')
   node.groupings = collect_children_by_id(loc, children, 'grouping')
   node.features = collect_children_by_id(loc, children, 'feature')
   node.extensions = collect_children_by_id(loc, children, 'extension')
   node.identities = collect_children_by_id(loc, children, 'identity')
   node.rpcs = collect_children_by_id(loc, children, 'rpc')
   node.notifications = collect_children_by_id(loc, children, 'notification')
   node.deviations = collect_children_by_id(loc, children, 'deviation')
   node.body = collect_body_children(loc, children)
end
local function init_typedef(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.type = require_child(loc, children, 'type')
   node.units = maybe_child_property(loc, children, 'units', 'value')
   node.default = maybe_child_property(loc, children, 'default', 'value')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
end
local function init_uses(node, loc, argument, children)
   node.id = require_argument(loc, argument)
   node.when = maybe_child_property(loc, children, 'when', 'value')
   node.if_features = collect_child_properties(children, 'if-feature', 'value')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
   node.typedefs = collect_children_by_id(loc, children, 'typedef')
   node.refines = collect_children(children, 'refine')
   node.augments = collect_children(children, 'augment')
end
local function init_value(node, loc, argument, children)
   local arg = require_argument(loc, argument)
   local as_num = tonumber(arg)
   assert_with_loc(as_num and math.floor(as_num) == as_num,
                   loc, 'not an integer: %s', arg)
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


-- 7.8.2.  The list's key Statement

-- The "key" statement, which MUST be present if the list represents
-- configuration, and MAY be present otherwise, takes as an argument a
-- string that specifies a space-separated list of leaf identifiers of
-- this list.  A leaf identifier MUST NOT appear more than once in the
-- key.  Each such leaf identifier MUST refer to a child leaf of the
-- list.  The leafs can be defined directly in substatements to the
-- list, or in groupings used in the list.
local function sanitize_lists (node)
   if node.kind == "list" and node.key then
      assert(node.body)
      local keys = {}
      for each in node.key:gmatch("([^%s]+)") do
         if keys[each] then
            error('duplicated leaf identifier in list '..node.id..' '..node.key)
         end
         keys[each] = true
      end
      for each in pairs(keys) do
         -- TODO: Should check leaf is defined, but it might not be found because
         -- was defined via uses.
         local leaf = node.body[each]
         if leaf then leaf.mandatory = true end
      end
   end
   for _, v in pairs(node) do
      if type(v) == "table" then
         sanitize_lists(v)
      end
   end
end

local function schema_from_ast(ast)
   local ret
   local submodules = {}
   for _,node in ipairs(ast) do
      if node.keyword == 'module' then
         assert(not ret, 'expected only one module form')
         ret = parse_node(node)
      elseif node.keyword == 'submodule' then
         assert(not submodules[node.id], 'duplicate submodule name: '..node.id)
         submodules[node.id] = parse_node(node)
      else
         error('expected only module and submodule statements, got: '..node.keyword)
      end
   end
   assert(ret, 'missing module form')
   ret.submodules = submodules
   sanitize_lists(ret)
   return ret
end

local function set(...)
   local ret = {}
   for k, v in pairs({...}) do ret[v] = true end
   return ret
end

local primitive_types = set(
   'int8', 'int16', 'int32', 'int64', 'uint8', 'uint16', 'uint32', 'uint64',
   'binary', 'bits', 'boolean', 'decimal64', 'empty', 'enumeration',
   'identityref', 'instance-identifier', 'leafref', 'string', 'union')

-- Inherits config attributes from parents
local function inherit_config(schema, config)
   if schema.config ~= nil then
      assert(not config or schema.config == false)
      config = schema.config
   elseif config ~= nil then
      schema = shallow_copy(schema)
      schema.config = config
   end

   if schema.body then
      schema.body = shallow_copy(schema.body)
      for name, node in pairs(schema.body) do
         schema.body[name] = inherit_config(node, config)
      end
   end

   return schema
end

local default_features = {}
function get_default_capabilities()
   local ret = {}
   for mod,features in pairs(default_features) do
      local feature_names = {}
      for feature,_ in pairs(features) do
         table.insert(feature_names, feature)
      end
      ret[mod] = { feature = feature_names }
   end
   return ret
end
function set_default_capabilities(capabilities)
   default_features = {}
   for mod,caps in pairs(capabilities) do
      default_features[mod] = {}
      for _,feature in ipairs(caps.feature) do
         default_features[mod][feature] = true
      end
   end
end

-- Inline "grouping" into "uses".
-- Inline "submodule" into "include".
-- Inline "imports" into "module".
-- Inline "typedef" into "type".
-- Resolve if-feature.
-- Warn on any "when", resolving them as being true.
-- Resolve all augment and refine nodes. (TODO)
function resolve(schema, features)
   if features == nil then features = default_features end
   local function pop_prop(node, prop)
      local val = node[prop]
      node[prop] = nil
      return val
   end
   local function lookup(env, prop, name)
      if not env then error(prop..' not found: '..name) end
      if not env[prop] or not env[prop][name] then
         return lookup(env.env, prop, name)
      end
      return env[prop][name]
   end
   local function lookup_lazy(env, prop, name)
      local val = lookup(env, prop, name)
      if type(val) == 'table' then return val end
      -- Force lazy expansion and memoize result.
      return val()
   end
   local visit
   local function visit_top_level(node, env, prop)
      assert(not env[prop])
      env[prop] = {}
      local p = lookup(env, 'prefix', '_')
      for k,v in pairs(pop_prop(node, prop) or {}) do
         env[prop][k] = visit(v, env)
         env[prop][p..':'..k] = env[prop][k]
      end
   end
   local function visit_lazy(tab, env)
      local ret = {}
      local prefix = lookup(env, 'prefix', '_')
      local function error_recursion()
      end
      for k,v in pairs(tab) do
         -- FIXME: Only add prefix:k if at top level.
         local state
         local function lazy()
            if state == 'visiting' then
               error('mutually recursive definitions: '..k)
            elseif state then
               return state
            else
               state = 'visiting'
            end
            state = visit(v, env)
            return state
         end
         ret[k] = lazy
         ret[prefix..':'..k] = ret[k]
      end
      return ret
   end
   function visit_type(node, env)
      node = shallow_copy(node)
      local success, typedef = pcall(lookup, env, 'typedefs', node.id)
      if success then
         -- Typedefs are lazy, so force their value.  We didn't use
         -- lookup_lazy because we don't want the pcall to hide errors
         -- from the lazy expansion.
         typedef = typedef()
         node.base_type = typedef
         node.primitive_type = assert(typedef.primitive_type)
      else
         -- If the type name wasn't bound, it must be primitive.
         assert(primitive_types[node.id], 'unknown type: '..node.id)
         if node.id == 'union' then
            local union = {}
            for _,type in ipairs(node.union) do
               table.insert(union, visit_type(type, env))
            end
            node.union = union
         end
         node.primitive_type = node.id
      end
      return node
   end
   function visit(node, env)
      node = shallow_copy(node)
      env = {env=env}
      if node.typedefs then
         -- Populate node.typedefs as a table of thunks that will
         -- lazily expand and memoize their result when called.  This
         -- is not only a performance optimization but also allows the
         -- typedefs to be mutually visible.
         env.typedefs = visit_lazy(pop_prop(node, 'typedefs'), env)
      end
      if node.groupings then
         -- Likewise expand groupings at their point of definition.
         env.groupings = visit_lazy(pop_prop(node, 'groupings'), env)
      end
      local when = pop_prop(node, 'when')
      if when then
         print('warning: assuming "when" condition to be true: '..when.value)
      end
      if node.kind == 'module' or node.kind == 'submodule' then
         visit_top_level(node, env, 'extensions')
         -- Because features can themselves have if-feature, expand them
         -- lazily.
         env.features = visit_lazy(pop_prop(node, 'features'), env)
         visit_top_level(node, env, 'identities')
         for _,prop in ipairs({'rpcs', 'notifications'}) do
            node[prop] = shallow_copy(node[prop])
            for k,v in pairs(node[prop]) do node[prop][k] = visit(v, env) end
         end
      end
      if node.kind == 'rpc' then
         if node.input then node.input = visit(node.input, env) end
         if node.output then node.output = visit(node.output, env) end
      end
      if node.kind == 'feature' then
         node.module_id = lookup(env, 'module_id', '_')
         if not (features[node.module_id] or {})[node.id] then
            node.unavailable = true
         end
      end
      for _,feature in ipairs(pop_prop(node, 'if_features') or {}) do
         local feature_node = lookup_lazy(env, 'features', feature)
         if node.kind == 'feature' then
            -- This is a feature that depends on a feature.  These we
            -- keep in the environment but if the feature is
            -- unavailable, we mark it as such.
            local mod, id = feature_node.module_id, feature_node.id
            if not (features[mod] or {})[id] then node.unavailable = true end
         elseif feature_node.unavailable then
            return nil, env
         end
      end
      if node.type then
         node.type = visit_type(node.type, env)
         if not node.primitive_type then
            node.primitive_type = node.type.primitive_type
         end
      end
      if node.body then
         node.body = shallow_copy(node.body)
         for k,v in pairs(node.body or {}) do
            if v.kind == 'uses' then
               -- Inline "grouping" into "uses".
               local grouping = lookup_lazy(env, 'groupings', v.id)
               node.body[k] = nil
               for k,v in pairs(grouping.body) do
                  assert(not node.body[k], 'duplicate identifier: '..k)
                  node.body[k] = v
               end
               -- TODO: Handle refine and augment statements.
            else
               node.body[k] = visit(v, env)
            end
         end
      end
      return node, env
   end
   local function include(dst, src)
      for k,v in pairs(src) do
         assert(dst[k] == nil or dst[k] == v, 'incompatible definitions: '..k)
         if not k:match(':') then dst[k] = v end
      end
   end
   local linked = {}
   local function link(node, env)
      if linked[node.id] then
         assert(linked[node.id] ~= 'pending', 'recursive import of '..node.id)
         local node, env = unpack(linked[node.id])
         return node, env
      end
      linked[node.id] = 'pending'
      node = shallow_copy(node)
      local module_env = {env=env, prefixes={}, extensions={}, features={},
                          identities={}, typedefs={}, groupings={},
                          module_id={_=node.id}}
      node.body = shallow_copy(node.body)
      node.rpcs = shallow_copy(node.rpcs)
      node.notifications = shallow_copy(node.notifications)
      for k,v in pairs(pop_prop(node, 'includes')) do
         local submodule = lookup(env, 'submodules', k)
         assert(submodule.belongs_to.id == node.id)
         submodule, submodule_env = link(submodule, env)
         include(module_env.extensions, submodule_env.extensions)
         include(module_env.features, submodule_env.features)
         include(module_env.identities, submodule_env.identities)
         include(module_env.typedefs, submodule_env.typedefs)
         include(module_env.groupings, submodule_env.groupings)
         include(node.body, submodule.body)
         include(node.rpcs, submodule.rpcs)
         include(node.notifications, submodule.notifications)
      end
      if node.prefix then
         assert(node.kind == 'module', node.kind)
         module_env.prefixes[node.prefix] = node.id
         module_env.prefix = {_=node.prefix}
      end
      for k,v in pairs(pop_prop(node, 'imports')) do
         assert(not module_env.prefixes[v.prefix], 'duplicate prefix')
         -- CHECKME: Discarding body from import, just importing env.
         -- Is this OK?
         local schema, env = load_schema_by_name(v.id, v.revision_date)
         local prefix = v.prefix
         module_env.prefixes[prefix] = schema.id
         for _,prop in ipairs({'extensions', 'features', 'identities',
                               'typedefs', 'groupings'}) do
            for k,v in pairs(env[prop]) do
               if not k:match(':') then
                  module_env[prop][prefix..':'..k] = v
               end
            end
         end
      end
      node, env = visit(node, module_env)
      -- The typedefs, groupings, identities, and so on of this module
      -- are externally visible for other modules that may import this
      -- one; save them and their environment.
      linked[node.id] = {node, env}
      return node, env
   end
   schema = shallow_copy(schema)
   return link(schema, {submodules=pop_prop(schema, 'submodules')})
end

local primitive_types = {
   ['ietf-inet-types']=set('ipv4-address', 'ipv6-address',
                           'ipv4-prefix', 'ipv6-prefix'),
   ['ietf-yang-types']=set('mac-address')
}

-- NB: mutates schema in place!
local function primitivize(schema)
   for k, _ in pairs(primitive_types[schema.id] or {}) do
      assert(schema.typedefs[k]).primitive_type = k
   end
   return schema
end

function parse_schema(src, filename)
   return schema_from_ast(parser.parse(src, filename))
end
function parse_schema_file(filename)
   return schema_from_ast(parser.parse_file(filename))
end

function load_schema(src, filename)
   local s, e = resolve(primitivize(parse_schema(src, filename)))
   return inherit_config(s), e
end
function load_schema_file(filename)
   local s, e = resolve(primitivize(parse_schema_file(filename)))
   return inherit_config(s), e
end
load_schema_file = util.memoize(load_schema_file)
function load_schema_by_name(name, revision)
   -- FIXME: @ is not valid in a Lua module name.
   -- if revision then name = name .. '@' .. revision end
   name = name:gsub('-', '_')
   return load_schema(require('lib.yang.'..name..'_yang'), name)
end
load_schema_by_name = util.memoize(load_schema_by_name)

function selftest()
   print('selftest: lib.yang.schema')
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
         description "Represents a piece of fruit";

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

   local schema, env = load_schema(test_schema)
   assert(schema.id == "fruit")
   assert(schema.namespace == "urn:testing:fruit")
   assert(schema.prefix == "fruit")
   assert(schema.contact == "John Smith fake@person.tld")
   assert(schema.organization == "Fruit Inc.")
   assert(schema.description == "Module to test YANG schema lib")

   -- Check all revisions are accounted for.
   assert(schema.revisions[1].description == "Revision 1")
   assert(schema.revisions[1].value == "2016-05-27")
   assert(schema.revisions[2].description == "Revision 2")
   assert(schema.revisions[2].value == "2016-05-28")

   -- Check that the feature statements are in the exports interface
   -- but not the schema itself.
   assert(not schema.features)
   assert(env.features["bowl"])
   -- Poke through lazy features abstraction by invoking thunk.
   assert(env.features["bowl"]().description == 'A fruit bowl')

   -- Check that groupings get inlined into their uses.
   assert(schema.body['fruit-bowl'])
   assert(schema.body['fruit-bowl'].description == 'Represents a fruit bowl')
   local contents = schema.body['fruit-bowl'].body['contents']
   assert(contents)
   assert(contents.kind == 'list')
   -- TODO: Copy description over?  Probably not given that one node
   -- can use multiple groupings.
   -- assert(contents.description == 'Represents a piece of fruit')
   assert(contents.body['name'].kind == 'leaf')
   assert(contents.body['name'].type.id == 'string')
   assert(contents.body["name"].mandatory == true)
   assert(contents.body["name"].description == "Name of fruit.")
   assert(contents.body["score"].type.id == "uint8")
   assert(contents.body["score"].mandatory == true)
   assert(contents.body["score"].type.range.value[1] == 0)
   assert(contents.body["score"].type.range.value[2] == 10)

   -- Check the container has a leaf called "description"
   local desc = schema.body["fruit-bowl"].body['description']
   assert(desc.type.id == "string")
   assert(desc.description == "About the bowl")

   parse_schema(require('lib.yang.ietf_yang_types_yang'))
   parse_schema(require('lib.yang.ietf_inet_types_yang'))

   load_schema_by_name('ietf-yang-types')
   load_schema_by_name('ietf-softwire')
   load_schema_by_name('snabb-softwire-v1')

   local inherit_config_schema = [[module config-inheritance {
      namespace cs;
      prefix cs;

      container foo {
         container bar {
            config false;

            leaf baz {
               type uint8;
            }
         }
      }

      grouping quux {
         leaf quuz {
            type uint8;
         }
      }

      container corge { uses quux; }
      container grault { config true; uses quux; }
      container garply { config false; uses quux; }
   }]]

   local icschema = load_schema(inherit_config_schema)

   -- Test things that should be null, still are.
   assert(icschema.config == nil)
   assert(icschema.body.foo.config == nil)

   -- Assert the regular config is propergated through container.
   assert(icschema.body.foo.body.bar.config == false)
   assert(icschema.body.foo.body.bar.body.baz.config == false)

   -- Now test the grouping, we need to ensure copying is done correctly.
   assert(icschema.body.corge.config == nil)
   assert(icschema.body.corge.body.quuz.config == nil)
   assert(icschema.body.grault.config == true)
   assert(icschema.body.grault.body.quuz.config == true)
   assert(icschema.body.garply.config == false)
   assert(icschema.body.garply.body.quuz.config == false)
   print('selftest: ok')
end
