module(..., package.seeall)

local lib = require('core.lib')
local conf = require('apps.lwaftr.conf')
local load_legacy_lwaftr_config = conf.load_legacy_lwaftr_config
local yang = require('lib.yang.yang')

local function show_usage(code)
   print(require("program.lwaftr.migrate_configuration.README_inc"))
   main.exit(code)
end

local function parse_args(args)
   local handlers = {}
   function handlers.h() show_usage(0) end
   args = lib.dogetopt(args, handlers, "h", { help="h" })
   if #args ~= 1 then show_usage(1) end
   return unpack(args)
end

function run(args)
   local conf_file = parse_args(args)
   local conf = load_legacy_lwaftr_config(conf_file)
   yang.print_data_for_schema_by_name('snabb-softwire-v1', conf, io.stdout)
   main.exit(0)
end
