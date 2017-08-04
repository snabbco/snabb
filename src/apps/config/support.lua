-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local app = require("core.app")
local app_graph_mod = require("core.config")
local path_mod = require("lib.yang.path")
local yang = require("lib.yang.yang")
local data = require("lib.yang.data")
local cltable = require("lib.cltable")

function compute_parent_paths(path)
   local function sorted_keys(t)
      local ret = {}
      for k, v in pairs(t) do table.insert(ret, k) end
      table.sort(ret)
      return ret
   end
   local ret = { '/' }
   local head = ''
   for _,part in ipairs(path_mod.parse_path(path)) do
      head = head..'/'..part.name
      table.insert(ret, head)
      local keys = sorted_keys(part.query)
      if #keys > 0 then
         for _,k in ipairs(keys) do
            head = head..'['..k..'='..part.query[k]..']'
         end
         table.insert(ret, head)
      end
   end
   return ret
end

local function add_child_objects(accum, grammar, config)
   local visitor = {}
   local function visit(grammar, config)
      assert(visitor[grammar.type])(grammar, config)
   end
   local function visit_child(grammar, config)
      if grammar.type == 'scalar' then return end
      table.insert(accum, config)
      return visit(grammar, config)
   end
   function visitor.table(grammar, config)
      -- Ctables are raw data, and raw data doesn't contain children
      -- with distinct identity.
      if grammar.key_ctype and grammar.value_ctype then return end
      local child_grammar = {type="struct", members=grammar.values,
                             ctype=grammar.value_ctype}
      if grammar.key_ctype then
         for k, v in cltable.pairs(config) do visit_child(child_grammar, v) end
      else
         for k, v in pairs(config) do visit_child(child_grammar, v) end
      end
   end
   function visitor.array(grammar, config)
      -- Children are leaves; nothing to do.
   end
   function visitor.struct(grammar, config)
      -- Raw data doesn't contain children with distinct identity.
      if grammar.ctype then return end
      for k,grammar in pairs(grammar.members) do
         local id = data.normalize_id(k)
         local child = config[id]
         if child ~= nil then visit_child(grammar, child) end
      end
   end
   return visit(grammar, config)
end

local function compute_objects_maybe_updated_in_place (schema_name, config,
                                                       changed_path)
   local schema = yang.load_schema_by_name(schema_name)
   local grammar = data.config_grammar_from_schema(schema)
   local objs = {}
   local getter, subgrammar
   for _,path in ipairs(compute_parent_paths(changed_path)) do
      -- Calling the getter is avg O(N) in depth, so that makes the
      -- loop O(N^2), though it is generally bounded at a shallow
      -- level so perhaps it's OK.  path_mod.resolver is O(N) too but
      -- memoization makes it O(1).
      getter, subgrammar = path_mod.resolver(grammar, path)
      -- Scalars can't be updated in place.
      if subgrammar.type == 'scalar' then return objs end
      table.insert(objs, getter(config))
      -- Members of raw data can't be updated in place either.
      if subgrammar.type == 'table' then
         if subgrammar.key_ctype and subgrammar.value_ctype then return objs end
      elseif subgrammar.type == 'struct' then
         if subgrammar.ctype then return objs end
      end
   end
   -- If the loop above finished normally, then it means that the
   -- object at changed_path might contain in-place-updatable objects
   -- inside of it, so visit its children.
   add_child_objects(objs, subgrammar, objs[#objs])
   return objs
end

local function record_mutable_objects_embedded_in_app_initarg (name, obj, accum)
   local function record(obj)
      local tab = accum[obj]
      if not tab then tab = {}; accum[obj] = tab end
      table.insert(tab, name)
   end
   local function visit(obj)
      if type(obj) == 'table' then
         record(obj)
         for _,v in pairs(obj) do visit(v) end
      elseif type(obj) == 'cdata' then
         record(obj)
         -- Cdata contains sub-objects but they don't have identity;
         -- it's only the cdata object itself that has identity.
      else
         -- Other object kinds can't be updated in place.
      end
   end
   visit(obj)
end

-- Return "in-place dependencies": a table mapping mutable object ->
-- list of app names.
local function compute_mutable_objects_embedded_in_app_initargs (app_graph)
   local deps = {}
   for name, info in pairs(app_graph.apps) do
      record_mutable_objects_embedded_in_app_initarg(name, info.arg, deps)
   end
   return deps
end

local function compute_apps_to_restart_after_configuration_update (
      schema_name, configuration, verb, changed_path, in_place_dependencies, arg)
   local maybe_updated = compute_objects_maybe_updated_in_place(
      schema_name, configuration, changed_path)
   local needs_restart = {}
   for _,place in ipairs(maybe_updated) do
      for _,appname in ipairs(in_place_dependencies[place] or {}) do
         needs_restart[appname] = true
      end
   end
   return needs_restart
end

local function add_restarts(actions, app_graph, to_restart)
   for _,action in ipairs(actions) do
      local name, args = unpack(action)
      if name == 'stop_app' or name == 'reconfig_app' then
         local appname = args[1]
         to_restart[appname] = nil
      end
   end
   local to_relink = {}
   for appname, _ in pairs(to_restart) do
      local info = assert(app_graph.apps[appname])
      local class, arg = info.class, info.arg
      if class.reconfig then
         table.insert(actions, {'reconfig_app', {appname, class, arg}})
      else
         table.insert(actions, {'stop_app', {appname}})
         table.insert(actions, {'start_app', {appname, class, arg}})
         to_relink[appname] = true
      end
   end
   for linkspec,_ in pairs(app_graph.links) do
      local fa, fl, ta, tl = app_graph_mod.parse_link(linkspec)
      if to_relink[fa] then
         table.insert(actions, {'link_output', {fa, fl, linkspec}})
      end
      if to_relink[ta] then
         table.insert(actions, {'link_input', {ta, tl, linkspec}})
      end
   end
   table.insert(actions, {'commit', {}})
   return actions
end


generic_schema_config_support = {
   compute_config_actions = function(
         old_graph, new_graph, to_restart, verb, path, ...)
      return add_restarts(app.compute_config_actions(old_graph, new_graph),
                          new_graph, to_restart)
   end,
   update_mutable_objects_embedded_in_app_initargs = function(
         in_place_dependencies, app_graph, schema_name, verb, path, arg)
      return compute_mutable_objects_embedded_in_app_initargs(app_graph)
   end,
   compute_apps_to_restart_after_configuration_update =
      compute_apps_to_restart_after_configuration_update,
   translators = {}
}

function load_schema_config_support(schema_name)
   local mod_name = 'apps.config.support.'..schema_name:gsub('-', '_')
   local success, support_mod = pcall(require, mod_name)
   if success then return support_mod.get_config_support() end
   return generic_schema_config_support
end
