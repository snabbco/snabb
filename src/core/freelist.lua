module(...,package.seeall)

local ffi = require("ffi")

function new (type, size)
   local element_ct = ffi.typeof(type)
   local fl_type = ffi.typeof("struct { int nfree, max; $ list[?]; }",
			      element_ct)
   return ffi.new(fl_type, size, 0, size)
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

