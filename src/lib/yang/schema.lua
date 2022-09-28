-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local lib = require("core.lib")
local mem = require("lib.stream.mem")
local parser = require("lib.yang.parser")
local util = require("lib.yang.util")
local maxpc = require("lib.maxpc")

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

local function parse_range_or_length_arg(loc, kind, range)
   local function parse_part(part)
      local l, r = part:match("^%s*([^%.]*)%s*%.%.%s*([^%s]*)%s*$")
      if not r then
         l = part:match("^%s*([^%.]*)%s*$")
         r = (l ~= 'min') and l
      end
      assert_with_loc(l and r, loc, 'bad range component: %s', part)
      if l ~= 'min' then l = util.tointeger(l) end
      if r ~= 'max' then r = util.tointeger(r) end
      if l ~= 'min' and l < 0 and kind == 'length' then
         error("length argument may not be negative: "..l)
      end
      if r ~= 'max' and r < 0 and kind == 'length' then
         error("length argument may not be negative: "..r)
      end
      if l ~= 'min' and r ~= 'max' and r < l then
         error("invalid "..kind..": "..part)
      end
      return { l, r }
   end
   local res = {}
   for part in range:split("|") do table.insert(res, parse_part(part)) end
   if #res == 0 then error_with_loc(loc, "empty "..kind, range) end
   return res
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
-- Must be one or 1 or 1.1.
local function init_yang_version (node, loc, argument, children)
   local arg = require_argument(loc, argument)
   assert_with_loc(arg == "1" or arg == "1.1", 'not a valid version number: %s', arg)
   node.value = tonumber(arg)
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
   node.bases = collect_child_properties(children, 'base', 'value')
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
   node.value = parse_range_or_length_arg(loc, node.kind,
                                          require_argument(loc, argument))
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
   node.value = parse_range_or_length_arg(loc, node.kind,
                                          require_argument(loc, argument))
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
end
local function init_enum(node, loc, argument, children)
   node.name = require_argument(loc, argument)
   local value = maybe_child_property(loc, children, 'value', 'value')
   if value then node.value = tonumber(value) end
   node.description = maybe_child_property(loc, children, 'description', 'value')
   node.reference = maybe_child_property(loc, children, 'reference', 'value')
   node.status = maybe_child_property(loc, children, 'status', 'value')
   node.if_features = collect_child_properties(children, 'if-feature', 'value')
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
   node.date = require_argument(loc, argument)
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
   node.length = maybe_child(loc, children, 'length')
   node.patterns = collect_children(children, 'pattern')
   node.enums = collect_children(children, 'enum')
   -- !!! path
   node.leafref = maybe_child_property(loc, children, 'path', 'value')
   node.require_instances = collect_children(children, 'require-instance')
   node.bases = collect_child_properties(children, 'base', 'value')
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
   init_natural, 'fraction-digits', 'position', 'min-elements', 'max-elements')
declare_initializer(init_yang_version, 'yang-version')
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
declare_initializer(init_enum, 'enum')
declare_initializer(init_refine, 'refine')
declare_initializer(init_revision, 'revision')
declare_initializer(init_rpc, 'rpc')
declare_initializer(init_submodule, 'submodule')
declare_initializer(init_type, 'type')
declare_initializer(init_typedef, 'typedef')
declare_initializer(init_uses, 'uses')
declare_initializer(init_value, 'value')

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
   return ret
end

local primitive_types = lib.set(
   'int8', 'int16', 'int32', 'int64', 'uint8', 'uint16', 'uint32', 'uint64',
   'binary', 'bits', 'boolean', 'decimal64', 'empty', 'enumeration',
   'identityref', 'instance-identifier', 'leafref', 'string', 'union')

-- Inherits config attributes from parents
local function inherit_config(schema)
   local function visit(node, config)
      if node.config == nil then
         node = shallow_copy(node)
         node.config = config
      elseif node.config == false then
         config = node.config
      else
         assert(config)
      end

      if node.body then
         node.body = shallow_copy(node.body)
         for name, child in pairs(node.body) do
            node.body[name] = visit(child, config)
         end
      end
      return node
   end
   return visit(schema, true)
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

-- Parse/interpret YANG 1.1 if-feature expressions
-- https://tools.ietf.org/html/rfc7950#section-7.20.2
local if_feature_expr_parser = (function ()
   local match, capture, combine = maxpc.import()
   local refs = {}
   local function ref (s) return function (...) return refs[s](...) end end
   local function wsp_lf()
      return combine._or(match.equal(' '), match.equal('\t'),
                         match.equal('\n'), match.equal('\r'))
   end
   local function sep()      return combine.some(wsp_lf()) end
   local function optsep()   return combine.any(wsp_lf())  end
   local function keyword(s) return match.string(s)        end
   local function identifier()
      -- [a-zA-Z_][a-zA-Z0-9_-.:]+
      local alpha_ = match.satisfies(function (x)
            return ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
               :find(x, 1, true)
      end)
      local digit_punct = match.satisfies(function (x)
            return ("0123456789-."):find(x, 1, true)
      end)
      return capture.subseq(
         match.seq(alpha_, combine.any(combine._or(alpha_, digit_punct)))
      )
   end
   local function identifier_ref()
      local idref = capture.seq(
         identifier(),
         combine.maybe(match.equal(":")), combine.maybe(identifier())
      )
      local function ast_idref (mod_or_id, _, id)
         return {'feature', id or mod_or_id, id and mod_or_id or nil}
      end
      return capture.unpack(idref, ast_idref)
   end
   local function if_feature_not()
      local not_feature = capture.seq(
         keyword'not', sep(), ref'if_feature_factor'
      )
      local function ast_not (_, _, fact) return {'not', fact} end
      return capture.unpack(not_feature, ast_not)
   end
   local function if_feature_subexpr()
      local subexpr = capture.seq(
         match.equal("("), optsep(), ref'if_feature_expr', optsep(), match.equal(")")
      )
      local function ast_subexpr (_, _, expr) return {'subexpr', expr} end
      return capture.unpack(subexpr, ast_subexpr)
   end
   local function if_feature_factor ()
      return combine._or(
         if_feature_not(), if_feature_subexpr(), identifier_ref()
      )
   end
   refs.if_feature_factor = if_feature_factor()
   local function if_feature_and()
      local and_feature = capture.seq(
         if_feature_factor(), sep(), keyword'and', sep(), ref'if_feature_term'
      )
      local function ast_and (a, _, _, _, b) return {'and', a, b} end
      return capture.unpack(and_feature, ast_and)
   end
   local function if_feature_term()
      return combine._or(if_feature_and(), if_feature_factor())
   end
   refs.if_feature_term = if_feature_term()
   local function if_feature_or()
      local or_feature = capture.seq(
         if_feature_term(), sep(), keyword'or', sep(), ref'if_feature_expr'
      )
      local function ast_or (a, _, _, _, b) return {'or', a, b} end
      return capture.unpack(or_feature, ast_or)
   end
   local function if_feature_expr()
      return combine._or(if_feature_or(), if_feature_term())
   end
   refs.if_feature_expr = if_feature_expr()
   return refs.if_feature_expr
end)()

local function parse_if_feature_expr(expr)
   local ast, success, eof = maxpc.parse(expr, if_feature_expr_parser)
   assert(success and eof, "Error parsing if-feature-expression: "..expr)
   return ast
end

local function interpret_if_feature(expr, has_feature_p)
   local function interpret (ast)
      local op, a, b = unpack(ast)
      if op == 'feature' then
         return has_feature_p(a, b)
      elseif op == 'or' then
         if interpret(a) then return true
         else                 return interpret(b) end
      elseif op == 'and' then
         return interpret(a) and interpret(b)
      elseif op == 'subexpr' then
         return interpret(a)
      end
   end
   return interpret(parse_if_feature_expr(expr))
end

-- Inline "grouping" into "uses".
-- Inline "submodule" into "include".
-- Inline "imports" into "module".
-- Inline "typedef" into "type".
-- Resolve if-feature, identity bases, and identityref bases.
-- Warn on any "when", resolving them as being true.
-- Resolve all augment nodes. (TODO)
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
   -- Resolve argument of "base" statements to identity fqid and collect in a list.
   local function resolve_bases(bases, env)
      local ret = {}
      for _, base in ipairs(bases) do
         table.insert(ret, lookup_lazy(env, 'identities', base).fqid)
      end
      return ret
   end
   local function visit_type(node, env)
      node = shallow_copy(node)
      local success, typedef = pcall(lookup, env, 'typedefs', node.id)
      if success then
         -- Typedefs are lazy, so force their value.  We didn't use
         -- lookup_lazy because we don't want the pcall to hide errors
         -- from the lazy expansion.
         typedef = typedef()
         assert(typedef.kind == "typedef")
         node.base_type = typedef
         node.primitive_type = assert(typedef.primitive_type)
         node.enums = {}
         for _, enum in ipairs(typedef.type.enums) do
            node.enums[enum.name] = true
         end
         node.union = typedef.type.union
      else
         -- If the type name wasn't bound, it must be primitive.
         assert(primitive_types[node.id], 'unknown type: '..node.id)
         if node.id == 'union' then
            local union = {}
            for _,type in ipairs(node.union) do
               table.insert(union, visit_type(type, env))
            end
            node.union = union
         elseif node.id == 'identityref' then
            node.bases = resolve_bases(node.bases, env)
            node.default_prefix = schema.id
         elseif node.id == 'enumeration' then
            local values = {}
            local max_value = -2147483648
            for i, enum in ipairs(node.enums) do
               assert(not node.enums[enum.name],
                      'duplicate name in enumeration: '..enum.name)
               node.enums[enum.name] = enum
               if enum.value then
                  assert(not values[enum.value],
                         'duplicate value in enumeration: '..enum.value)
                  values[enum.value] = true
                  max_value = math.max(enum.value, max_value)
               elseif i == 1 then
                  max_value = 0
                  enum.value = max_value
               elseif max_value < 2147483647 then
                  max_value = max_value + 1
                  enum.value = max_value
               else
                  error('explicit value required in enum: '..enum.name)
               end
            end
         end
         node.primitive_type = node.id
      end
      return node
   end
   -- Already made "local" above.
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
         -- Because features can themselves have if-feature, and
         -- identities can reference each other, expand them lazily.
         env.features = visit_lazy(pop_prop(node, 'features'), env)
         env.identities = visit_lazy(pop_prop(node, 'identities'), env)
         for _,prop in ipairs({'rpcs', 'notifications'}) do
            node[prop] = shallow_copy(node[prop])
            for k,v in pairs(node[prop]) do node[prop][k] = visit(v, env) end
         end
         local last_revision = nil
         for _,revision in ipairs(node.revisions) do
            if last_revision == nil or last_revision < revision.date then
               last_revision = revision.date
            end
         end
         node.last_revision = last_revision
      end
      if node.kind == 'rpc' then
         if node.input then node.input = visit(node.input, env) end
         if node.output then node.output = visit(node.output, env) end
      end
      if node.kind == 'identity' then
         -- Attach fully-qualified identity.
         node.fqid = lookup(env, 'module_id', '_')..":"..node.id
         node.bases = resolve_bases(node.bases, env)
      end
      if node.kind == 'feature' then
         node.module_id = lookup(env, 'module_id', '_')
         if not (features[node.module_id] or {})[node.id] then
            node.unavailable = true
         end
      end
      for _,expr in ipairs(pop_prop(node, 'if_features') or {}) do
         local function resolve_feature (feature, mod)
            assert(not mod, "NYI: module qualified features in if-feature expression")
            local feature_node = lookup_lazy(env, 'features', feature)
            if node.kind == 'feature' then
               -- This is a feature that depends on a feature.  These we
               -- keep in the environment but if the feature is
               -- unavailable, we mark it as such.
               local mod, id = feature_node.module_id, feature_node.id
               if (features[mod] or {})[id] then return true
               else node.unavailable = true end
            elseif not feature_node.unavailable then
               return true
            end
         end
         if not interpret_if_feature(expr, resolve_feature) then
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
         local body = node.body
         node.body = {}
         for k,v in pairs(body) do
            if v.kind == 'uses' then
               -- Inline "grouping" into "uses".
               local grouping = lookup_lazy(env, 'groupings', v.id)
               for k,v in pairs(grouping.body) do
                  assert(not node.body[k], 'duplicate identifier: '..k)
                  node.body[k] = v
               end
               for _,refine in ipairs(v.refines) do
                  local target = node.body[refine.node_id]
                  assert(target, 'missing refine node: '..refine.node_id)
                  -- FIXME: Add additional "must" statements.
                  for _,k in ipairs({'config', 'description', 'reference',
                                     'presence', 'default', 'mandatory',
                                     'min_elements', 'max_elements'}) do
                     if refine[k] ~= nil then target[k] = refine[k] end
                  end
               end
               -- TODO: Handle augment statements.
            else
               assert(not node.body[k], 'duplicate identifier: '..k)
               node.body[k] = visit(v, env)
            end
         end
      end
      -- Mark "key" children of lists as being mandatory.
      if node.kind == 'list' and node.key then
         for k in node.key:split(' +') do
            local leaf = assert(node.body[k])
            leaf.mandatory = true
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
   ['ietf-inet-types']=lib.set('ipv4-address', 'ipv6-address',
                           'ipv4-prefix', 'ipv6-prefix'),
   ['ietf-yang-types']=lib.set('mac-address')
}

-- NB: mutates schema in place!
local function primitivize(schema)
   for k, _ in pairs(primitive_types[schema.id] or {}) do
      assert(schema.typedefs[k]).primitive_type = k
   end
   return schema
end

function parse_schema(src, filename)
   return schema_from_ast(parser.parse(mem.open_input_string(src, filename)))
end
function parse_schema_file(filename)
   return schema_from_ast(parser.parse(assert(file.open(filename))))
end

local function collect_uniqueness (s)
   local leaves = {}
   local function mark (id)
      if leaves[id] then return false end
      leaves[id] = true
      return true
   end
   local function visit (node)
      if not node then return end
      for k,v in pairs(node) do
         if type(v) == 'table' then
            visit(v)
         else
            if k == 'kind' and v == 'leaf' then
               node.is_unique = mark(node.id)
            end
         end
      end
   end
   visit(s)
   return s
end

function load_schema(src, filename)
   local s, e = resolve(primitivize(parse_schema(src, filename)))
   return collect_uniqueness(inherit_config(s)), e
end
function load_schema_file(filename)
   local s, e = resolve(primitivize(parse_schema_file(filename)))
   return collect_uniqueness(inherit_config(s)), e
end
load_schema_file = util.memoize(load_schema_file)

function load_schema_source_by_name(name, revision)
   -- FIXME: @ is not valid in a Lua module name.
   -- if revision then name = name .. '@' .. revision end
   name = name:gsub('-', '_')
   return require('lib.yang.'..name..'_yang')
end

function load_schema_by_name(name, revision)
   return load_schema(load_schema_source_by_name(name, revision))
end
load_schema_by_name = util.memoize(load_schema_by_name)

function add_schema(src, filename)
   -- Assert that the source actually parses, and get the ID.
   local s, e = load_schema(src, filename)
   -- Assert that this schema isn't known.
   assert(not pcall(load_schema_source_by_name, s.id))
   assert(s.id)
   -- Intern.
   package.loaded['lib.yang.'..s.id:gsub('-', '_')..'_yang'] = src
   return s.id
end

function add_schema_file(filename)
   local file_in = assert(io.open(filename))
   local contents = file_in:read("*a")
   file_in:close()
   return add_schema(contents, filename)
end

function lookup_identity (fqid)
   local schema_name, id = fqid:match("^([^:]*):(.*)$")
   local schema, env = load_schema_by_name(schema_name)
   local id_thunk = env.identities[id]
   if not id_thunk then
      error('no identity '..id..' in module '..schema_name)
   end
   return id_thunk() -- Force the lazy lookup.
end
lookup_identity = util.memoize(lookup_identity)

function identity_is_instance_of (identity, fqid)
   for _, base in ipairs(identity.bases) do
      if base == fqid then return true end
      local base_id = lookup_identity(base)
      if identity_is_instance_of(base_id, fqid) then return true end
   end
   return false
end
identity_is_instance_of = util.memoize(identity_is_instance_of)

function selftest()
   print('selftest: lib.yang.schema')

   set_default_capabilities(get_default_capabilities())

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

      identity foo;
      identity bar { base foo; }
      identity baz { base bar; base foo; }

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
   assert(schema.last_revision == "2016-05-28")

   -- Check all revisions are accounted for.
   assert(schema.revisions[1].description == "Revision 1")
   assert(schema.revisions[1].date == "2016-05-27")
   assert(schema.revisions[2].description == "Revision 2")
   assert(schema.revisions[2].date == "2016-05-28")

   -- Check that the feature statements are in the exports interface
   -- but not the schema itself.
   assert(not schema.features)
   assert(env.features["bowl"])
   -- Poke through lazy features abstraction by invoking thunk.
   assert(env.features["bowl"]().description == 'A fruit bowl')

   -- Poke through lazy identity bases by invoking thunk.
   assert(#env.identities["baz"]().bases == 2)
   assert(#env.identities["bar"]().bases == 1)
   assert(env.identities["bar"]().bases[1] == 'fruit:foo')
   assert(#env.identities["foo"]().bases == 0)

   assert(#lookup_identity("ietf-alarms:alarm-identity").bases == 0)

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
   local equal = require('core.lib').equal
   assert(equal(contents.body["score"].type.range.value, {{0, 10}}))

   -- Check the container has a leaf called "description"
   local desc = schema.body["fruit-bowl"].body['description']
   assert(desc.type.id == "string")
   assert(desc.description == "About the bowl")

   parse_schema(require('lib.yang.ietf_yang_types_yang'))
   parse_schema(require('lib.yang.ietf_inet_types_yang'))

   load_schema_by_name('ietf-yang-types')

   -- We could save and restore capabilities to avoid the persistent
   -- side effect, but it would do no good:  the schemas would be
   -- memoized when the features were present.  So just add to the
   -- capabilities, for now, assuming tests are run independently from
   -- programs.
   local caps = get_default_capabilities()
   local new_caps = { ['ietf-softwire-br'] = {feature={'binding-mode'}} }
   for mod_name, mod_caps in pairs(new_caps) do
      if not caps[mod_name] then caps[mod_name] = {feature={}} end
      for _,feature in ipairs(mod_caps.feature) do
         table.insert(caps[mod_name].feature, feature)
      end
   end
   set_default_capabilities(caps)

   load_schema_by_name('ietf-softwire-common')
   load_schema_by_name('ietf-softwire-br')
   load_schema_by_name('snabb-softwire-v3')

   local br = load_schema_by_name('ietf-softwire-br')
   local binding = br.body['br-instances'].body['br-type'].body['binding']
   assert(binding)
   local bt = binding.body['binding'].body['bind-instance'].body['binding-table']
   assert(bt)
   local ps = bt.body['binding-entry'].body['port-set']
   assert(ps)
   local alg = br.body['br-instances'].body['br-type'].body['algorithm']
   assert(not alg)
   -- The binding-entry grouping is defined in ietf-softwire-common and
   -- imported by ietf-softwire-br, but with a refinement that the
   -- default is 0.  Test that the refinement was applied.
   assert(ps.body['psid-offset'].default == "0")

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
   assert(icschema.config == true)
   assert(icschema.body.foo.config == true)

   -- Assert the regular config is propergated through container.
   assert(icschema.body.foo.body.bar.config == false)
   assert(icschema.body.foo.body.bar.body.baz.config == false)

   -- Now test the grouping, we need to ensure copying is done correctly.
   assert(icschema.body.corge.config == true)
   assert(icschema.body.corge.body.quuz.config == true)
   assert(icschema.body.grault.config == true)
   assert(icschema.body.grault.body.quuz.config == true)
   assert(icschema.body.garply.config == false)
   assert(icschema.body.garply.body.quuz.config == false)

   -- Test Range with explicit value.
   assert(lib.equal(parse_range_or_length_arg(nil, nil, "42"), {{42, 42}}))

   -- Parsing/interpreting if-feature expressions
   local function test_features (i, m)
      local f = { b_99 = { ["c.d"] = true },
                  [0] = { bar = true } }
      return f[m or 0][i]
   end
   local expr = "baz and foo or bar and (a or b_99:c.d)"
   assert(interpret_if_feature(expr, test_features))
   assert(not interpret_if_feature("boo", test_features))
   assert(not interpret_if_feature("baz or foo", test_features))

   print('selftest: ok')
end
