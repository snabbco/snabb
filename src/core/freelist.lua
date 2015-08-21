module(...,package.seeall)

local ffi = require("ffi")
local shm = require('core.shm')

local function maketype(elmtype, size)
   return ffi.typeof([[
      struct {
         int nfree, max;
         $ list[$];
      } ]], elmtype, size)
end

local function type_to_name(elmtype)
   return tostring(elmtype)
      :gsub('^ctype<(.*)>$', '%1')
      :gsub('[^%w*]+', '_'):gsub('*', '#')
end

function new (elmtype, size)
   elmtype = ffi.typeof(elmtype)
   return shm.map('/freelists/'..type_to_name(elmtype), maketype(elmtype, size))
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
