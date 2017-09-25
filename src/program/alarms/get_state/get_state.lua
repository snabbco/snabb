module(..., package.seeall)

local common = require("program.config.common")

function show_usage(command, status, err_msg)
   if err_msg then print('error: '..err_msg) end
   print(require("program.alarms.get_state.README_inc"))
   main.exit(status)
end

function run (args)
   local opts = { command='get-alarms-state', with_path=true, is_config=false,
                  usage = show_usage }
   args = common.parse_command_line(args, opts)
   local response = common.call_leader(
      args.instance_id, 'get-alarms-state',
      { schema = 'ietf-alarms',
        path = args.path, print_default = args.print_default,
        format = args.format })
   common.print_and_exit(response, "state")
end
