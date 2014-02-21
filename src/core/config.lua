-- 'config' is a data structure that describes an app network.

module(..., package.seeall)

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
--   arg is the app's configuration (as a string to be passed to new()).
--
-- Example: config.app(c, "nic", Intel82599, [[{pciaddr = "0000:00:01.00"}]])
function app (config, name, class, arg)
   arg = arg or "nil"
   assert(type(name) == "string", "name must be a string")
   assert(type(class) == "table", "class must be a table")
   assert(type(arg)   == "string", "arg must be a string")
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

link_syntax = [[ *(%w+).(%w+) *-> *(%w+).(%w+) *]]

function format_link (fa, fl, ta, tl)
   return ("%s.%s -> %s.%s"):format(fa, fl, ta, tl)
end

function canonical_link (spec)
   return format_link(parse_link(spec))
end

-- Return a Lua object for the arg to an app.
-- Example:
--   parse_app_arg("{ timeout = 5 * 10 }") => { timeout = 50 }
function parse_app_arg (s)
   print("s", type(s), s)
   assert(type(s) == 'string')
   return loadstring("return " .. s)()
end

