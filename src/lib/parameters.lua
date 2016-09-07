-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local function values(t)
   local ret = {}
   for k, v in pairs(t) do ret[v] = true end
   return ret
end

-- Given PARAMETERS, a table of parameters, assert that all of the
-- REQUIRED keys are present, fill in any missing values from OPTIONAL,
-- and error if any unknown keys are found.
--
-- parameters := { k=v, ... }
-- required := { k, ... }
-- optional := { k=v, ... }
-- k, v := not nil
function parse(parameters, required, optional)
   local ret = {}
   if parameters == nil then parameters = {} end
   required = values(required)
   if optional == nil then optional = {} end
   for k, _ in pairs(required) do
      if parameters[k] == nil then error('missing required option ' .. k) end
   end
   for k, v in pairs(parameters) do
      if not required[k] and optional[k] == nil then
         error('unrecognized option ' .. k)
      end
      ret[k] = v
   end
   for k, v in pairs(optional) do
      if ret[k] == nil then ret[k] = v end
   end
   return ret
end

function selftest ()
   print('selftest: lib.parameters')
   local equal = require('core.lib').equal
   local function assert_equal(parameters, required, optional, expected)
      assert(equal(parse(parameters, required, optional), expected))
   end
   local function assert_error(parameters, required, optional)
      assert(not pcall(parse, parameters, required, optional))
   end

   local req = {'a', 'b'}
   local opt = {c=42, d=43}

   assert_equal({a=1, b=2}, req, opt, {a=1, b=2, c=42, d=43})
   assert_equal({a=1, b=2}, req, {}, {a=1, b=2})
   assert_equal({a=1, b=2, c=30}, req, opt, {a=1, b=2, c=30, d=43})
   assert_equal({a=1, b=2, d=10}, req, opt, {a=1, b=2, c=42, d=10})
   assert_equal({d=10}, {}, opt, {c=42, d=10})
   assert_equal({}, {}, opt, {c=42, d=43})
   assert_equal({d=false}, {}, opt, {c=42, d=false})
   assert_equal({d=nil}, {}, opt, {c=42, d=43})
   assert_equal({a=false, b=2}, req, {}, {a=false, b=2})

   assert_error({}, req, opt)
   assert_error({d=30}, req, opt)
   assert_error({a=1}, req, opt)
   assert_error({b=1}, req, opt)
   assert_error({a=nil, b=2}, req, opt)
   assert_error({a=1, b=nil}, req, opt)
   assert_error({a=1, b=2, d=10, e=100}, req, opt)
   assert_error({a=1, b=2, c=4}, req, {})
   assert_error({a=1, b=2}, {}, {})
   print('selftest: ok')
end
