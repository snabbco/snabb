module("freelist",package.seeall)

function new (type, size)
   return { nfree = 0,
            -- XXX Better LuaJIT idiom for specifying the array type?
            list = ffi.new(type.."[?]", size) }
end

function add (freelist, element)
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

