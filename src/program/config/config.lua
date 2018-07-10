-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local lib = require("core.lib")

local function show_usage(status)
   print(require("program.config.README_inc"))
   main.exit(status)
end

local function parse_args(args)
   local handlers = {}
   handlers.h = function() show_usage(0) end
   args = lib.dogetopt(args, handlers, "h", {help="h"})
   if #args < 1 then show_usage(1) end
   return args
end

function run(args)
   args = parse_args(args)
   local command = string.gsub(table.remove(args, 1), "-", "_")
   local modname = ("program.config.%s.%s"):format(command, command)
   require(modname).run(args)
end
