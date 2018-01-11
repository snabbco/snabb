module(..., package.seeall)

local lib = require("core.lib")

-- Retrieves latest version from CHANGELOG.md.
-- Format: ## [Version] - 2017-31-12.
local function latest_version()
   local filename = "program/lwaftr/doc/CHANGELOG.md"
   local regex = "^## %[([^%]]+)%] %- (%d%d%d%d%-%d%d%-%d%d)"
   for line in io.lines(filename) do
      local version, date = line:match(regex)
      if version and date then return version, date end
   end
end

local function show_usage(exit_code)
   local content = require("program.lwaftr.README_inc")
   local version, date = latest_version()
   if version and date then
      content = ("Version: %s (%s)\n\n"):format(version, date)..content
   end
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
