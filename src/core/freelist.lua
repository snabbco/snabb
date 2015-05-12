module(...,package.seeall)

local ffi = require("ffi")

local named_lists = {}

function share_lists(f)
   f(named_lists)
end

function receive_shared(t)
   for k,v in pairs(t) do
      local typ = ffi.typeof([[
         struct {
            int nfree, max;
            $ list[?];
         }*
      ]], ffi.typeof(v[1]))
      local list = ffi.cast(typ, v[2])
      named_lists[k] = {v[1], list}
   end
end


function new (type, size, name)
   if name and named_lists[name] then
      return named_lists[name][2]
   end

   local typ = ffi.typeof([[
      struct {
         int nfree, max;
         $ list[?];
      }
   ]], ffi.typeof(type))
   local list = typ(size, {nfree=0, max=size})
   if name then
      named_lists[name] = {type, list}
   end
   return list
end

function add (freelist, element)
   -- Safety check
   if _G.developer_debug then assert(freelist.nfree < freelist.max, "freelist overflow") end
   freelist.list[freelist.nfree] = element
   freelist.nfree = freelist.nfree + 1
end

function remove (freelist)
   if freelist.nfree == 0 then
      error("no free packets")
   else
      freelist.nfree = freelist.nfree - 1
      return freelist.list[freelist.nfree]
   end
end

function nfree (freelist)
   return freelist.nfree
end

