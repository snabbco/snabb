module(..., package.seeall)

local ffi = require("ffi")
local ctable = require("lib.ctable")

function build(keys, values)
   return setmetatable({ keys = keys, values = values },
                       {__index=get, __newindex=set})
end

function new(params)
   local ctable_params = {}
   for k,v in _G.pairs(params) do ctable_params[k] = v end
   assert(not ctable_params.value_type)
   ctable_params.value_type = ffi.typeof('uint32_t')
   return build(ctable.new(ctable_params), {})
end

function get(cltable, key)
   local entry = cltable.keys:lookup_ptr(key)
   if not entry then return nil end
   return cltable.values[entry.value]
end

function set(cltable, key, value)
   local entry = cltable.keys:lookup_ptr(key)
   if entry then
      cltable.values[entry.value] = value
      if value == nil then cltable.keys:remove_ptr(entry) end
   elseif value ~= nil then
      local idx = #cltable.values + 1
      cltable.values[idx] = value
      cltable.keys:add(key, idx)
   end
end

function pairs(cltable)
   local ctable_next, ctable_max, ctable_entry = cltable.keys:iterate()
   return function()
      ctable_entry = ctable_next(ctable_max, ctable_entry)
      if not ctable_entry then return end
      return ctable_entry.key, cltable.values[ctable_entry.value]
   end
end

function selftest()
   print("selftest: cltable")

   local ipv4 = require('lib.protocol.ipv4')
   local params = { key_type = ffi.typeof('uint8_t[4]') }
   local cltab = new(params)

   for i=0,255 do
      local addr = ipv4:pton('1.2.3.'..i)
      cltab[addr] = 'hello, '..i
   end

   for i=0,255 do
      local addr = ipv4:pton('1.2.3.'..i)
      assert(cltab[addr] == 'hello, '..i)
   end

   for i=0,255 do
      -- Remove value that is present.
      cltab[ipv4:pton('1.2.3.'..i)] = nil
      -- Remove value that is not present.
      cltab[ipv4:pton('2.3.4.'..i)] = nil
   end

   for k,v in pairs(cltab) do error('not reachable') end

   print("selftest: ok")
end
