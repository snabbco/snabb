module(..., package.seeall)

local counter = require("core.counter")
local lib = require("core.lib")
local data = require("lib.yang.data")
local state = require("lib.yang.state")
local lwutil = require("apps.lwaftr.lwutil")

local write_to_file = lwutil.write_to_file

function load_requested_counters(counters)
   local result = dofile(counters)
   assert(type(result) == "table", "Not a valid counters file: "..counters)
   return result
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

function regen_counters(counters, outfile)
   local cnames = lwutil.keys(counters)
   table.sort(cnames)
   local out_val = {'return {'}
   for _,k in ipairs(cnames) do
      table.insert(out_val, string.format('   ["%s"] = %s,', k, counters[k]))
   end
   table.insert(out_val, '}\n')
   write_to_file(outfile, (table.concat(out_val, '\n')))
end
