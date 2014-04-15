--- index set object: keeps a set of indexed values
local NDX_mt = {}
NDX_mt.__index = NDX_mt

-- trivial constructor
function NDX_mt:new (max, name)
   return setmetatable({
      __nxt = 0,
      __max = max,
      __name = name,
   }, self)
end

-- add a value to the set
-- if new, returns a new index and true
-- if it already existed, returns given index and false
function NDX_mt:add (v)
   assert(self.__nxt < self.__max, self.__name.." overflow")
   if self[v] then
      return self[v], false
   end
   self[v] = self.__nxt
   self.__nxt = self.__nxt + 1
   return self[v],true
end

return NDX_mt