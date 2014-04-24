local index_set = require "lib.index_set"

local function _t(a, b)
   return tostring(a)..'/'..tostring(b)
end

return {
   basic_handling = function ()
      local ndx_set = index_set:new(4, 'test ndx')
      assert (_t(ndx_set:add('a'))=='0/true', "indexes start with 0, and is new")
      assert (_t(ndx_set:add('b'))=='1/true', "second new index")
      assert (_t(ndx_set:add('c'))=='2/true', "third new")
      assert (_t(ndx_set:add('b'))=='1/false', "that's an old one")
      assert (_t(ndx_set:add('a'))=='0/false', "the very first one")
      assert (_t(ndx_set:add('A'))=='3/true', "almost, but new")
      assert (_t(pcall(ndx_set.add, ndx_set,'B'))
         :match('^false/lib/index_set.lua:%d+: test ndx overflow'), 'should overflow')   end
}
