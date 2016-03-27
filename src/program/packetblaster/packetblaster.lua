-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local lib = require("core.lib")

local function show_usage(exit_code)
  print(require("program.packetblaster.README_inc"))
  main.exit(exit_code)
end

function run(args)
  if #args == 0 then show_usage(1) end
  local command = string.gsub(table.remove(args, 1), "-", "_")
  local modname = ("program.packetblaster.%s.%s"):format(command, command)
  if not lib.have_module(modname) then
    show_usage(1)
  end
  require(modname).run(args)
end
