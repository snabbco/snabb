module(...,package.seeall)

local utils = require('pf.utils')

local program_name = 'pflua-quickcheck'

local seed, iterations, prop_name, prop_args, prop, prop_info

-- Due to limitations of Lua 5.1, finding if a command failed is convoluted.
local function find_gitrev()
   local fd = io.popen('git rev-parse HEAD 2>/dev/null ; echo -n "$?"')
   local cmdout = fd:read("*all")
   fd:close() -- Always true in 5.1, with Lua or LuaJIT
   local _, _, git_ret = cmdout:find("(%d+)$")
   git_ret = tonumber(git_ret)
   if git_ret ~= 0 then -- Probably not in a git repo
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

local function rerun_usage(i)
   print(("Rerun as: %s --seed=%s --iterations=%s %s %s"):
         format(program_name, seed, i + 1,
                prop_name, table.concat(prop_args, " ")))
end

function initialize(options)
   seed, iterations, prop_name, prop_args =
      options.seed, options.iterations, options.prop_name, options.prop_args

   if not seed then
      seed = math.floor(utils.gmtime() * 1e6) % 10^9
      print("Using time as seed: "..seed)
   end
   math.randomseed(assert(tonumber(seed)))

   if not iterations then iterations = 1000 end

   if not prop_name then
      error("No property name specified")
   end

   prop = require(prop_name)
   if prop.handle_prop_args then
      prop_info = prop.handle_prop_args(prop_args)
   else
      assert(#prop_args == 0,
             "Property does not take options "..prop_name)
      prop_info = nil
   end
end

function initialize_from_command_line(args)
   local options = {}
   while #args >= 1 and args[1]:match("^%-%-") do
      local arg, _, val = table.remove(args, 1):match("^%-%-([^=]*)(=(.*))$")
      assert(arg)
      if arg == 'seed' then options.seed = assert(tonumber(val))
      elseif arg == 'iterations' then options.iterations = assert(tonumber(val))
      else error("Unknown argument: " .. arg) end
   end
   if #args < 1 then
      print("Usage: " ..
               program_name ..
               " [--seed=SEED]" ..
               " [--iterations=ITERATIONS]" ..
               " property_file [property_specific_args]")
      os.exit(1)
   end
   options.prop_name = table.remove(args, 1)
   options.prop_args = args
   initialize(options)
end

function run()
   if not prop then
      error("Call initialize() or initialize_from_command_line() first")
   end

   for i = 1,iterations do
      -- Wrap property and its arguments in a 0-arity function for xpcall
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
          print(expected) -- This is an error code and traceback in this case
          rerun_usage(i)
          os.exit(1)
      end
      if not utils.equals(expected, got) then
          print_gitrev_if_available()
          print("The property was falsified.")
          -- If the property file has extra info available, show it
          if prop.print_extra_information then
             prop.print_extra_information()
          else
             print('Expected:')
             utils.pp(expected)
             print('Got:')
             utils.pp(got)
          end
          rerun_usage(i)
          os.exit(1)
      end
   end
   print(iterations.." iterations succeeded.")
end
