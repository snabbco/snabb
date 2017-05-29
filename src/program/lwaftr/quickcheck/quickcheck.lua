module(...,package.seeall)

local lib = require("core.lib")
local utils = require("program.lwaftr.quickcheck.utils")

local function show_usage(code)
   print(require("program.lwaftr.quickcheck.README_inc"))
   main.exit(code)
end

local function parse_args (args)
   local handlers = {}
   local opts = {
      iterations = 100,
   }
   function handlers.h() show_usage(0) end
   handlers["seed"] = function (arg)
      opts["seed"] = assert(tonumber(arg), "seed must be a number")
   end
   handlers["iterations"] = function (arg)
		opts["iterations"] = assert(tonumber(arg), "iterations must be a number")
   end
   args = lib.dogetopt(args, handlers, "h",
      { help="h", ["seed"] = 0, ["iterations"] = 0 })
   if #args == 0 then show_usage(1) end
   if not opts.seed then
      local seed = math.floor(utils.gmtime() * 1e6) % 10^9
      print("Using time as seed: "..seed)
      opts.seed = seed
   end
   local prop_name = table.remove(args, 1)

   return opts, prop_name, args
end

-- Due to limitations of Lua 5.1, finding if a command failed is convoluted.
local function find_gitrev()
   local fd = io.popen('git rev-parse HEAD 2>/dev/null ; echo -n "$?"')
   local cmdout = fd:read("*all")
   fd:close() -- Always true in 5.1, with Lua or LuaJIT.
   local _, _, git_ret = cmdout:find("(%d+)$")
   git_ret = tonumber(git_ret)
   if git_ret ~= 0 then -- Probably not in a git repo.
      return nil
   else
      local _, _, sha1 = cmdout:find("(%x+)")
      return sha1
   end
end

local function print_gitrev_if_available()
   local rev = find_gitrev()
   if rev then print(("Git revision %s"):format(rev)) end
end

local function initialize_property (name, args)
   local prop = require(name)
   if not prop.handle_prop_args then
      assert(#args == 0, "Property does not take options "..name)
   end
   return prop, prop.handle_prop_args(args)
end

function run (args)
   local opts, prop_name, prop_args = parse_args(args)
   local rerun_usage = function (i)
      print(("Rerun as: snabb lwaftr quickcheck --seed=%s --iterations=%s %s %s"):
            format(opts.seed, i + 1, prop_name, table.concat(prop_args, " ")))
   end
   math.randomseed(opts.seed)

   local prop, prop_info = initialize_property(prop_name, prop_args)
   for i=1,opts.iterations do
      -- Wrap property and its arguments in a 0-arity function for xpcall.
      local wrap_prop = function() return prop.property(prop_info) end
      local propgen_ok, expected, got = xpcall(wrap_prop, debug.traceback)
      if not propgen_ok then
          print(("Crashed generating properties on run %s."):format(i))
          if prop.print_extra_information then
             print("Attempting to print extra information; it may be wrong.")
             if not pcall(prop.print_extra_information)
                then print("Something went wrong printing extra info.")
             end
          end
          print("Traceback (this is reliable):")
          print(expected) -- This is an error code and traceback in this case.
          rerun_usage(i)
          main.exit(1)
      end
      if not utils.equals(expected, got) then
          print_gitrev_if_available()
          print("The property was falsified.")
          -- If the property file has extra info available, show it.
          if prop.print_extra_information then
             prop.print_extra_information()
          else
             print('Expected:')
             utils.pp(expected)
             print('Got:')
             utils.pp(got)
          end
          rerun_usage(i)
          main.exit(1)
      end
   end
   print(opts.iterations.." iterations succeeded.")

   if prop.cleanup then prop.cleanup() end
end
