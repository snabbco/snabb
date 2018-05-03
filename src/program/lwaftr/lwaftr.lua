module(..., package.seeall)

local lib = require("core.lib")

local function latest_version()
   local v = require('core.version')
   return v.version, v.extra_version
end

local function show_usage(exit_code)
   local content = require("program.lwaftr.README_inc")
   require('core.main').version()
   print('')
   print(content)
   main.exit(exit_code)
end

function run(args)
   if #args == 0 then show_usage(1) end
   local command = string.gsub(table.remove(args, 1), "-", "_")
   local modname = ("program.lwaftr.%s.%s"):format(command, command)
   if not lib.have_module(modname) then
      show_usage(1)
   end
   require(modname).run(args)
end
