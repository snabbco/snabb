-- Support for basic OO programming.  Copied from
-- http://lua-users.org/wiki/InheritanceTutorial with a few
-- modifications.
--
-- Usage:
-- local require("lib.lua.class")
-- local myclass = subClass(baseClass | nil, [constructor_method, ...])
--
-- myclass inherits all public methods and class variables from
-- baseClass as well as all constructor methods. The default
-- constructor method is called new().  Each constructor executes the
-- method called _init_<construcor> if it exists, where <constructor>
-- is the name of the constructor method.  All arguments supplied to
-- the constructor are passed unmodified to the corresponding _init
-- method.
--
function subClass (baseClass, ... )
   local new_class = {}
   local class_mt = {__index = new_class}
   local constructors = {...}

   if baseClass ~= nil then
      setmetatable(new_class, {__index = baseClass})
      for c, _ in pairs(baseClass.constructors) do
	 new_class.constructors[c] = true
      end
   else
      new_class.constructors = {new = true}
   end
   for _, c in ipairs(constructors) do
      assert(not new_class.constructors[c],
	     "duplicate declaration of constructor method "..c)
      new_class.constructors[c] = true
   end

   for c, _ in pairs(new_class.constructors) do
      new_class[c] =
	 function (self, ...)
	    local newinst = {}
	    setmetatable(newinst, class_mt)
	    if newinst['_init_'..c] then
	       newinst['_init_'..c](newinst, ...)
	    end
	    return newinst
	 end
   end

   -- Return the class object of the instance
   function new_class:class ()
      return new_class
   end

   -- Return the super class object of the instance
   function new_class:superClass ()
      return baseClass
   end

   -- Return true if the caller is an instance of theClass
   function new_class:isa (theClass)
      local b_isa = false
      local cur_class = new_class

      while (cur_class ~= nil) and (b_isa == false) do
	 if cur_class == theClass then
	    b_isa = true
	 else
	    cur_class = cur_class:superClass()
	 end
      end
      return b_isa
   end

   return new_class
end
