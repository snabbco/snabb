module(..., package.seeall)

local lib = require('core.lib')
local yang = require('lib.yang.yang')

function show_usage(code)
   print(require('program.lwaftr.compile_configuration.README_inc'))
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
   local filein, fileout = parse_args(args)
   local success, err = pcall(yang.load_configuration, filein,
                              {schema_name='snabb-softwire-v3', compiled_filename=fileout})
   if not success then
      print(tostring(err))
      main.exit(1)
   end
end
