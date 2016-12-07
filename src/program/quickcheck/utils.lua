module(...,package.seeall)

local S = require("syscall")

function gmtime()
   local tv = S.gettimeofday()
   local secs = tonumber(tv.tv_sec)
   secs = secs + tonumber(tv.tv_usec) * 1e-6
   return secs
end

function concat(a, b)
   local ret = {}
   for _, v in ipairs(a) do table.insert(ret, v) end
   for _, v in ipairs(b) do table.insert(ret, v) end
   return ret
end

function equals(expected, actual)
   if type(expected) ~= type(actual) then return false end
   if type(expected) == 'table' then
      for k, v in pairs(expected) do
         if not equals(v, actual[k]) then return false end
      end
      for k, _ in pairs(actual) do
         if expected[k] == nil then return false end
      end
      return true
   else
      return expected == actual
   end
end

function is_array(x)
   if type(x) ~= 'table' then return false end
   if #x == 0 then return false end
   for k,v in pairs(x) do
      if type(k) ~= 'number' then return false end
      -- Restrict to unsigned 32-bit integer keys.
      if k < 0 or k >= 2^32 then return false end
      -- Array indices are integers.
      if k - math.floor(k) ~= 0 then return false end
      -- Negative zero is not a valid array index.
      if 1 / k < 0 then return false end
   end
   return true
end

function pp(expr, indent, suffix)
   indent = indent or ''
   suffix = suffix or ''
   if type(expr) == 'number' then
      print(indent..expr..suffix)
   elseif type(expr) == 'string' then
      print(indent..'"'..expr..'"'..suffix)
   elseif type(expr) == 'boolean' then
      print(indent..(expr and 'true' or 'false')..suffix)
   elseif is_array(expr) then
      assert(#expr > 0)
      if #expr == 1 then
         if type(expr[1]) == 'table' then
            print(indent..'{')
            pp(expr[1], indent..'  ', ' }'..suffix)
         else
            print(indent..'{ "'..expr[1]..'" }'..suffix)
         end
      else
         if type(expr[1]) == 'table' then
            print(indent..'{')
            pp(expr[1], indent..'  ', ',')
         else
            print(indent..'{ "'..expr[1]..'",')
         end
         indent = indent..'  '
         for i=2,#expr-1 do pp(expr[i], indent, ',') end
         pp(expr[#expr], indent, ' }'..suffix)
      end
   elseif type(expr) == 'table' then
      if #expr == 0 then
         print(indent .. '{}')
      else
         error('unimplemented')
      end
   else
      error("unsupported type "..type(expr))
   end
   return expr
end

function assert_equals(expected, actual)
   if not equals(expected, actual) then
      pp(expected)
      pp(actual)
      error('not equal')
   end
end

function choose(choices)
   local idx = math.random(#choices)
   return choices[idx]
end

function choose_with_index(choices)
   local idx = math.random(#choices)
   return choices[idx], idx
end

function selftest ()
   print("selftest: pf.utils")
   local tab = { 1, 2, 3 }
   assert_equals({ 1, 2, 3, 1, 2, 3 }, concat(tab, tab))
   local gu1 = gmtime()
   local gu2 = gmtime()
   assert(gu1, gu2)
   print("OK")
end
