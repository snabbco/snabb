module(..., package.seeall)

local lib = require('core.lib')
local address_map = require("apps.lwaftr.address_map")

function show_usage(code)
   print(require("program.snabb_lwaftr.compile_address_map.README_inc"))
   main.exit(code)
end

function parse_args(args)
   local handlers = {}
   function handlers.h() show_usage(0) end
   args = lib.dogetopt(args, handlers, "h", { help="h" })
   if #args < 1 or #args > 2 then show_usage(1) end
   return unpack(args)
end

function run(args)
   local in_file, out_file = parse_args(args)
   local map = address_map.compile(in_file)
   if not out_file then out_file = in_file:gsub("%.txt$", "")..'.map' end
   local success, err = pcall(address_map.save, map, out_file)
   if not success then
      io.stderr:write(err..'\n')
      main.exit(1)
   end
   main.exit(0)
end
