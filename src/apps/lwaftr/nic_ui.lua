local nic_common = require("apps.lwaftr.nic_common")
local lib        = require("core.lib")

local usage="nic_ui binding_table_file conf_file inet_nic_pci b4side_nic_pci"

function run(parameters)
   local opts = { verbose = true }
   local handlers = {}
   function handlers.v () opts.verbose = true  end
   function handlers.u () opts.ultra_verbose = true opts.verbose = true end
   function handlers.D (arg)
      opts.duration = assert(tonumber(arg), "duration must be a number")
   end
   function handlers.h () print(usage) main.exit(0) end

   parameters = lib.dogetopt(parameters, handlers, "vuhD:",
         { verbose="v", ultraverbose="u", help="h", duration="D" })
   if not (#parameters == 4) then handlers.h() end
   local bt_file, conf_file, inet_nic_pci, b4side_nic_pci = unpack(parameters)
   nic_common.run(bt_file, conf_file, inet_nic_pci, b4side_nic_pci, opts)
end

run(main.parameters)
