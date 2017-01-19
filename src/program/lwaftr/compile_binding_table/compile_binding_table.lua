module(..., package.seeall)

local lib = require('core.lib')
local stream = require("apps.lwaftr.stream")
local binding_table = require("apps.lwaftr.binding_table")

function show_usage(code)
   print(require("program.lwaftr.compile_binding_table.README_inc"))
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
   if not out_file then out_file = in_file:gsub("%.txt$", "")..'.o' end
   -- We use the stream module because it gives us the mtime.
   local input_stream = stream.open_input_text_stream(in_file)
   local success, bt_or_err = pcall(binding_table.load_source, input_stream)
   if not success then
      io.stderr:write(tostring(bt_or_err)..'\n')
      main.exit(1)
   end
   bt_or_err:save(out_file, stream.mtime_sec, stream.mtime_nsec)
   main.exit(0)
end
