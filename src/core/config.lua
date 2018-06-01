-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- 'config' is a data structure that describes an app network.

module(..., package.seeall)

local lib = require("core.lib")

-- API: Create a new configuration.
-- Initially there are no apps or links.
function new ()
   return {
      apps = {},         -- list of {name, class, args}
      links = {}         -- table with keys like "a.out -> b.in"
   }
end

-- API: Add an app to the configuration.
--
-- config.app(c, name, class, arg):
--   c is a config object.
--   name is the name of this app in the network (a string).
--   class is the Lua object with a class:new(arg) method to create the app.
--   arg is the app's configuration (to be passed to new()).
--
-- Example: config.app(c, "nic", Intel82599, {pciaddr = "0000:00:01.00"})
function app (config, name, class, arg)
   assert(type(name) == "string", "name must be a string")
   assert(type(class) == "table", "class must be a table")
   if class.config then
      local status, result = pcall(parse_app_arg, arg, class.config)
      if status then arg = result
      else error("failed to configure '"..name.."': "..result) end
   end
   config.apps[name] = { class = class, arg = arg}
end

-- API: Add a link to the configuration.
--
-- Example: config.link(c, "nic.tx -> vm.rx")
function link (config, spec)
   config.links[canonical_link(spec)] = true
end

-- Given "a.out -> b.in" return "a", "out", "b", "in".
function parse_link (spec)
   local fa, fl, ta, tl = spec:gmatch(link_syntax)()
   if fa and fl and ta and tl then
      return fa, fl, ta, tl
   else
      error("link parse error: " .. spec)
   end
end

link_syntax = [[ *([%w_]+)%.([%w_]+) *-> *([%w_]+)%.([%w_]+) *]]

function format_link (fa, fl, ta, tl)
   return ("%s.%s -> %s.%s"):format(fa, fl, ta, tl)
end

function canonical_link (spec)
   return format_link(parse_link(spec))
end

-- Parse Lua object for the arg to an app based on config. Arg may be a table
-- or a string encoded Lua object.
function parse_app_arg (arg, config)
   if type(arg) == 'string' then arg = lib.load_string(arg) end
   return lib.parse(arg, config)
end

function graphviz (c)
   local viz = 'digraph config {\n'
   local function trim (name) return name:sub(0, 12) end
   for linkspec,_ in pairs(c.links) do
      local fa, fl, ta, tl = config.parse_link(linkspec)
      viz = viz..'  '..trim(fa).." -> "..trim(ta)..' [taillabel="'..fl..'" headlabel="'..tl..'"]\n'
   end
   viz = viz..'}\n'
   return viz
end
