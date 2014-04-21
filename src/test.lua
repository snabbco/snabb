local ffi = require("ffi")
local C   = ffi.C
local main = require("core.main")

local shortlogs = false
local results = {fails=0}

local function show_log()
   io.write(string.format('\n======= %d tests, %d failures\n', #results, results.fails))
   for _,log in ipairs(results) do
      if #log.out > 0 then
         io.write(log.ok and '[Ok]\t' or '[FAIL]\t', log.name, ':\n')
         for _,line in ipairs(log.out) do
            io.write(line, '\n')
         end
         io.write('------\n')
      end
   end
end

local function log(name, ok, ...)
   results[#results+1] = {name=name or '---', ok=ok, out={...}}
   if not ok then results.fails = results.fails+1 end
   return ok
end

local function do_test(name, test, showlog)
   if showlog and name ~= '' then io.write('======= ', name, '\n') end
   local function gettb(err) 
      return debug.traceback(err, 2)
         :gsub('\n[^\n]*xpcall\'%s*test.lua:.*$', '\n\t['..name..']') 
   end
   
   if type(test) == 'function' then      -- perform the test
--      log(name, xpcall(test, gettb))
      io.write(log(name, xpcall(test, gettb)) and '[Ok]\t' or '[FAIL]\t', name, '\n')
      
   elseif type(test) == 'table' then      -- test every non '_xxx' item
      for k, v in pairs(test) do
         if test.__setup then 
            if not log (nil, xpcall(test.__setup, gettb, test, k, v)) then return end
         end
         if string.sub(k, 1, 1) ~= '_' then
            do_test(name..'.'..((type(k)=='string' or type(v)~='string') and k or v), v, showlog)
         end
      end
      
   elseif type(test) == 'string' then
      if io.open(test..'.lua', 'r') then         -- load test(s) from a file
         do_test(name, assert(loadfile(test..'.lua'))())
      else                                      -- last resort: a directory
         for fn in io.popen('ls -1F "'..test..'" 2>/dev/null'):lines() do
            if fn:match('_t%.lua$') then               -- found a test file
               do_test(name..'.'..fn:sub(1, -5), test..'/'..fn:sub(1, -5))
                  
            elseif fn:sub(-1) == '/' then               -- subdirectory: recurse
               do_test(name..'.'..fn:sub(1, -2), test..'/'..fn:sub(1, -2))
            end
         end
      end
   end
   if showlog and name ~= '' then show_log() end
end

do_test('', main.parameters, true)
return function(tn) do_test(tn, tn, true) end