module(..., package.seeall)

local app = require("core.app")
local config = require("core.config")
local counter = require("core.counter")
local lib = require("core.lib")
local setup = require("program.lwaftr.setup")

local counters_dir = "app/lwaftr/counters/"
local counter_names = {
-- Ingress.
   "in-ipv4-bytes",
   "in-ipv4-packets",
   "in-ipv6-bytes",
   "in-ipv6-packets",
-- Egress IP.
   "out-ipv4-bytes",
   "out-ipv4-packets",
   "out-ipv6-bytes",
   "out-ipv6-packets",
-- Egress ICMP.
   "out-icmpv4-bytes",
   "out-icmpv4-packets",
   "out-icmpv6-bytes",
   "out-icmpv6-packets",
-- Hairpinning.
   "hairpin-ipv4-bytes",
   "hairpin-ipv4-packets",
}

function show_usage(code)
   print(require("program.lwaftr.check.README_inc"))
   main.exit(code)
end

function parse_args(args)
   local handlers = {}
   function handlers.h() show_usage(0) end
   args = lib.dogetopt(args, handlers, "h", { help="h" })
   if #args ~= 5 and #args ~= 6 then show_usage(1) end
   return unpack(args)
end

function load_requested_counters(counters)
   return dofile(counters)
end

function read_counters(c)
   local results = {}
   for _, name in ipairs(counter_names) do
      local cnt = counter.open(counters_dir .. name, "readonly")
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

function run(args)
   local conf_file, inv4_pcap, inv6_pcap, outv4_pcap, outv6_pcap, counters_path =
      parse_args(args)

   local conf = require('apps.lwaftr.conf').load_lwaftr_config(conf_file)

   local c = config.new()
   setup.load_check(c, conf, inv4_pcap, inv6_pcap, outv4_pcap, outv6_pcap)
   app.configure(c)
   if counters_path then
      local initial_counters = read_counters(c)
      app.main({duration=0.10})
      local final_counters = read_counters(c)
      local counters_diff = diff_counters(final_counters, initial_counters)
      local req_counters = load_requested_counters(counters_path)
      validate_diff(counters_diff, req_counters)
   else
      app.main({duration=0.10})
   end
   print("done")
end
