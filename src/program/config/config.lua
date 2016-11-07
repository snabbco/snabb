module(..., package.seeall)

local usage = require("program.config.README_inc")

function run(args)
   -- Display usage if we have no arguments.
   if #args <= 0 then
      print(usage)
      main.exit(1)
   end

   local command = string.gsub(table.remove(args, 1), "-", "_")
   local modname = ("program.config.%s.%s"):format(command, command)
   require(modname).run(args)
end
