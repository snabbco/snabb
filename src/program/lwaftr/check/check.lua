module(..., package.seeall)

local config = require("core.config")
local counter = require("core.counter")
local lib = require("core.lib")
local lwconf = require('apps.lwaftr.conf')
local lwcounter = require("apps.lwaftr.lwcounter")
local lwutil = require("apps.lwaftr.lwutil")
local setup = require("program.lwaftr.setup")

-- Get the counter directory and names from the code, so that any change
-- in there will be automatically picked up by the tests.
local counter_names = lwcounter.counter_names
local counters_dir = lwcounter.counters_dir

local write_to_file = lwutil.write_to_file

function show_usage(code)
   print(require("program.lwaftr.check.README_inc"))
   main.exit(code)
end

function parse_args (args)
   local handlers = {}
   local opts = {}
   function handlers.h() show_usage(0) end
   function handlers.r() opts.r = true end
   handlers["on-a-stick"] = function ()
      opts["on-a-stick"] = true
   end
   handlers.D = function(dur)
      opts["duration"] = tonumber(dur)
   end
   args = lib.dogetopt(args, handlers, "hrD:",
      { help="h", regen="r", duration="D", ["on-a-stick"] = 0 })
   if #args ~= 5 and #args ~= 6 then show_usage(1) end
   if not opts["duration"] then opts["duration"] = 0.10 end
   return opts, args
end

function load_requested_counters(counters)
   local result = dofile(counters)
   assert(type(result) == "table", "Not a valid counters file: "..counters)
   return result
end

function read_counters(c)
   local results = {}
   for _, name in ipairs(counter_names) do
      local cnt = counter.open(counters_dir .. name .. ".counter", "readonly")
      results[name] = counter.read(cnt)
   end
   return results
end

function diff_counters(final, initial)
   local results = {}
   for name, ref in pairs(initial) do
      local cur = final[name]
      if cur ~= ref then
         results[name] = tonumber(cur - ref)
      end
   end
   return results
end

function validate_diff(actual, expected)
   if not lib.equal(actual, expected) then
      local msg
      print('--- Expected (actual values in brackets, if any)')
      for k, v in pairs(expected) do
         msg = k..' = '..v
         if actual[k] ~= nil then
            msg = msg..' ('..actual[k]..')'
         end
         print(msg)
      end
      print('--- actual (expected values in brackets, if any)')
      for k, v in pairs(actual) do
         msg = k..' = '..v
         if expected[k] ~= nil then
            msg = msg..' ('..expected[k]..')'
         end
         print(msg)
      end
      error('counters did not match')
   end
end

local function regen_counters(counters, outfile)
   local cnames = lwutil.keys(counters)
   table.sort(cnames)
   local out_val = {'return {'}
   for _,k in ipairs(cnames) do
      table.insert(out_val, string.format('   ["%s"] = %s,', k, counters[k]))
   end
   table.insert(out_val, '}\n')
   write_to_file(outfile, (table.concat(out_val, '\n')))
end

function run(args)
   local opts, args = parse_args(args)
   local load_check = opts["on-a-stick"] and setup.load_check_on_a_stick
                                         or  setup.load_check
   local conf_file, inv4_pcap, inv6_pcap, outv4_pcap, outv6_pcap, counters_path =
      unpack(args)
   local conf = lwconf.load_lwaftr_config(conf_file)

   local c = config.new()
   setup.load_check(c, conf, inv4_pcap, inv6_pcap, outv4_pcap, outv6_pcap)
   engine.configure(c)
   if counters_path then
      local initial_counters = read_counters(c)
      engine.main({duration=opts.duration})
      local final_counters = read_counters(c)
      local counters_diff = diff_counters(final_counters, initial_counters)
      if opts.r then
         regen_counters(counters_diff, counters_path)
      else
         local req_counters = load_requested_counters(counters_path)
         validate_diff(counters_diff, req_counters)
      end
   else
      engine.main({duration=opts.duration})
   end
   print("done")
end
