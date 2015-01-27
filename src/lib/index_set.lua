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


-- search a specific index
function NDX_mt:search(ndx)
   if type(ndx) ~= 'number' or math.floor(ndx) ~= ndx then
      return nil
   end
   for k, v in pairs(self) do
      if v == ndx and k ~= '__nxt' and k ~= '__max' then
         return k
      end
   end
   return nil
end

-- add a value to the set
-- if new, returns a new index and true
-- if it already existed, returns given index and false
function NDX_mt:add (v)
   if self[v] then
      return self[v], false
   end
   assert(self.__nxt < self.__max, self.__name.." overflow")
   self[v] = self.__nxt
   while self:search(self.__nxt) ~= nil do
      self.__nxt = self.__nxt + 1
   end
   return self[v],true
end


-- remove a key from the set
-- return the value
function NDX_mt:pop(k)
   local v = self[k]
   self[k] = nil
   if v ~= nil then
      self.__nxt = math.min(self.__nxt, v)
   end
   return v
end


---- tests

local function tests()
   -- #1: straight fill
   do
      local set1 = NDX_mt:new(4, 't#1')
      for i = 0, 3 do
         local ndx, nw = set1:add(('t1-s%d'):format(i))
         assert (ndx == i and nw == true, ('should get straight in order new values (%d %s, %s)'):format(i, ndx, nw))
      end
      local ok, ndx, nw = pcall(set1.add, set1, 'should fail')
      assert (not ok and ndx:match('t#1 overflow$'), ('didn\'t fail? (%s, %q)'):format(ok, ndx))
   end

   -- remove last
   do
      local set1 = NDX_mt:new(4, 't#2')
      for i = 0, 3 do
         local ndx, nw = set1:add(('t2-s%d'):format(i))
      end
      local v = set1:pop('t2-s3')
      assert (v == 3, 'wrong value popped')
      local ndx, nw = set1:add('t2-z400')
      assert (ndx == 3 and nw, 'wrong reinserted value')
   end

   -- remove at middle
   do
      local set1 = NDX_mt:new(4, 't#3')
      for i = 0, 2 do
         local ndx, nw = set1:add(('t3-s%d'):format(i))
      end
      local v = set1:pop('t3-s1')
      assert (v == 1, 'wrong value popped')
      local ndx, nw = set1:add('t2-z400')
      assert (ndx == 1 and nw, ('wrong first reinserted value (%s, %s)'):format(ndx, nw))
      local ndx, nw = set1:add('t2-z500')
      assert (ndx == 3 and nw, ('wrong last reinserted value (%s, %s)'):format(ndx, nw))
   end
   print ('ok')
end

if (...) == '-t' then tests() end



return NDX_mt
