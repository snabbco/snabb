module(...,package.seeall)

local ffi = require("ffi")

function new (type, size)
   return { nfree = 0,
            max = size,
            -- XXX Better LuaJIT idiom for specifying the array type?
            list = ffi.new(type.."[?]", size) }
end

function add (freelist, element)
   -- Safety check
   if _G.developer_debug then assert(freelist.nfree < freelist.max, "freelist overflow") end
   freelist.list[freelist.nfree] = element
   freelist.nfree = freelist.nfree + 1
end

function remove (freelist)
   if freelist.nfree == 0 then
      return nil
   else
      freelist.nfree = freelist.nfree - 1
      return freelist.list[freelist.nfree]
   end
end

function nfree (freelist)
   return freelist.nfree
end

