-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local lib = require("core.lib")

function run (args)
   if #args == 0 or args[1] == "--help" or args[1] == "-h" then
      print(require("program.wall.README_inc"))
      main.exit(1)
   end

   local command = string.gsub(table.remove(args, 1), "-", "_")
   local modname = string.format("program.wall.%s.%s", command, command)
   if not lib.have_module(modname) then
      print("No such command: " .. command)
      print(require("program.wall.README_inc"))
      main.exit(1)
   end

   require(modname).run(args)
end
