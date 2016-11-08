module(..., package.seeall)

Promise = {}
Promise.__index = Promise

local function is_promise(val)
   return type(val) == 'table' and val.and_then
end

local function curry(f, ...)
   local curried_args = { ... }
   if #curried_args == 0 then return f end
   return function(...)
      local args = { ... }
      for i=#curried_args, 1, -1 do
         table.insert(args, 1, curried_args[i])
      end
      return f(unpack(args))
   end
end

function new(transform, ...)
   if transform then
      transform = curry(transform, ...)
   else
      transform = function(...) return ... end
   end
   
   local ret = {
      resolved = false,
      next = nil,
      transform = transform
   }
   return setmetatable(ret, Promise)
end

function Promise:dispatch_next()
   assert(self.next)
   assert(self.resolved)
   self.next:resolve(unpack(self.vals))
end

function Promise:resolve(...)
   assert(not self.resolved)
   self.resolved = true
   self.vals = { self.transform(...) }
   if #self.vals == 1 and is_promise(self.vals[1]) then
      if self.next then self.vals[1]:chain(self.next) end
      self.next = self.vals[1]
   else
      if self.next then self:dispatch_next() end
   end
end

function Promise:chain(next)
   assert(next)
   assert(not self.next)
   self.next = next
   if self.resolved then self:dispatch_next() end
   return next
end

function Promise:and_then(f, ...)
   return self:chain(new(f, ...))
end

function Wait(s)
   local p = new()
   timer.activate(timer.new("wait", function() p:resolve() end, s * 1e9))
   return p
end
