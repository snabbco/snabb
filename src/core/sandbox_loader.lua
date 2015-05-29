
local ffi = require ('ffi')
local C = ffi.C

-- BEGIN Lua State handling functions

ffi.cdef [[
   /*
    * copied from lua.h
    */

   typedef struct lua_State lua_State;
   typedef double lua_Number;


   static const int LUA_GLOBALSINDEX = (-10002);
   static const int LUA_MULTRET = (-1);

   // basic types
   enum {
      LUA_TNONE = (-1),
      LUA_TNIL,
      LUA_TBOOLEAN,
      LUA_TLIGHTUSERDATA,
      LUA_TNUMBER,
      LUA_TSTRING,
      LUA_TTABLE,
      LUA_TFUNCTION,
      LUA_TUSERDATA,
      LUA_TTHREAD,
   };


   void lua_close (lua_State *L);
   void lua_createtable (lua_State *L, int narr, int nrec);
   void lua_getfield (lua_State *L, int index, const char *k);
   int lua_gettop (lua_State *L);
   int lua_next (lua_State *L, int index);
   int lua_pcall (lua_State *L, int nargs, int nresults, int errfunc);
   void lua_pushboolean (lua_State *L, int b);
   void lua_pushlightuserdata (lua_State *L, void *p);
   void lua_pushlstring (lua_State *L, const char *s, size_t len);
   void lua_pushnil (lua_State *L);
   void lua_pushnumber (lua_State *L, lua_Number n);
   void lua_pushvalue (lua_State *L, int index);
   void lua_settable (lua_State *L, int index);
   void lua_settop (lua_State *L, int index);
   int lua_toboolean (lua_State *L, int index);
   const char *lua_tolstring (lua_State *L, int index, size_t *len);
   lua_Number lua_tonumber (lua_State *L, int index);
   int lua_type (lua_State *L, int index);

   int luaL_loadbuffer (lua_State *L, const char *buff, size_t sz, const char *name);
   lua_State *luaL_newstate (void);
   void luaL_openlibs (lua_State *L);
]]

local lua_State_t = ffi.typeof ('lua_State')
local lua_State_mt = {}
lua_State_mt.__index = lua_State_mt


-- FFI object constructor.
-- creates the Lua State and loads standard libraries.
function lua_State_mt:__new()
   local vm = C.luaL_newstate()
   assert(vm ~= nil, "Couldn't allocate new LuaState")
   C.luaL_openlibs(vm)
   return vm
end


-- compiles a chunk of code and leaves the resultant function in the stack.
-- returns self or false and an error message
function lua_State_mt:load(code, name)
   if not code then return self end

   if C.luaL_loadbuffer(self, code, #code, '@'..(name or code:match('[^\n]*'))) ~= 0 then
      local err = ffi.string(C.lua_tolstring(self, -1, nil))
      self:close()
      return false, string.format("Error loading %q: %s", name, err)
   end
   return self
end


-- pushes several values into the vm stack.
-- handles only simple values: nil, boolean, numbers (double floats),
-- strings, tables (only key/values of known types, non-cyclic)
-- userdata and cdata are pushed as lightuserdata values
function lua_State_mt:push_values(...)
   local narg = select('#', ...)
   local prevtop = C.lua_gettop(self)
   for i = 1, narg do
      local v = select(i, ...)
      local typ = type(v)
      if typ == 'nil' then
         C.lua_pushnil(self)
      elseif typ == 'boolean' then
         C.lua_pushboolean(self, v)
      elseif typ == 'number' then
         C.lua_pushnumber(self, v)
      elseif typ == 'string' then
         C.lua_pushlstring(self, v, #v)
      elseif typ == 'table' then
         C.lua_createtable(self, 0, 0)
         for k1, v1 in pairs(v) do
            self:push_values(k1, v1)
            C.lua_settable(self, -3)
         end
      elseif typ == 'userdata' or typ == 'cdata' then
         C.lua_pushlightuserdata(self, v)
      end
   end
   return C.lua_gettop(self) - prevtop
end

-- returns a variable number of values from the stack
-- of the vm, optinally pops those values.
-- num (optional): number of values to read.  defaults to all values
-- keep (optional): boolean flag, if true, keeps the values in the stack
--  if false, removes the values it reads.
local pv_sz = ffi.new('size_t[?]', 1)
function lua_State_mt:pull_values(num, keep)
   local narg = C.lua_gettop(self)
   num = num or narg
   local o = {}
   for i = narg-num+1, narg do
      local typ, v = C.lua_type(self, i), nil
      if typ == C.LUA_TNIL then
         v = nil
      elseif typ == C.LUA_TBOOLEAN then
         v = C.lua_toboolean(self, i) ~= 0
      elseif typ == C.LUA_TNUMBER then
         v = C.lua_tonumber(self, i)
      elseif typ == C.LUA_TSTRING then
         local buf = C.lua_tolstring(self, i, pv_sz)
         v = ffi.string(buf, pv_sz[0])
      elseif typ == C.LUA_TTABLE then
         v = {}
         C.lua_pushnil(self)
         while C.lua_next(self, i) ~= 0 do
            local k1, v1 = self:pull_values(2, true)
            v[k1] = v1
            C.lua_settop(self, -2)
         end
      end
      o[i-narg+num] = v
   end
   if not keep then
      C.lua_settop(self, narg-num)
   end
   return unpack(o)
end


-- calls a function in the Lua State.
-- the first argument should be either:
--   - the name of a function in the global environment
--   - nil to call a function in the top of the stack
-- the rest of the arguments are sent to the function
-- according to the limitations of push_values().
-- returns (true, result values) if successful or
-- (false, error) if any error is raised (similar to standard pcall())
function lua_State_mt:pcall(fname, ...)
   if fname ~= nil then
      C.lua_getfield(self, C.LUA_GLOBALSINDEX, fname)
   end
   local prevtop = C.lua_gettop(self)-1

   local nargs, err = self:push_values(...)
   if not nargs then return nargs, err end

   if C.lua_pcall(self, nargs, C.LUA_MULTRET, 0) ~= 0 then
      local err = ffi.string(C.lua_tolstring(self, -1, nil))
      C.lua_settop(self, prevtop)
      return false, err
   end

   return true, self:pull_values(C.lua_gettop(self)-prevtop)
end


-- calls a nullary function in the Lua State
-- fname is the name of a function in the global environment
-- it's called without any arguments, discarding any returned value
function lua_State_mt:pcall_null(fname)
   C.lua_getfield(self, C.LUA_GLOBALSINDEX, fname)
   if C.lua_pcall(self, 0, 0, 0) ~= 0 then
      local err = ffi.string(C.lua_tolstring(self, -1, nil))
      C.lua_settop(self, C.lua_gettop(self)-2)
      return false, err
   end
   return true
end


-- copy the given table into the global space of the vm
function lua_State_mt:add_globals(t)
   for k, v in pairs(t) do
      self:push_values(k, v)
      C.lua_settable(self, C.LUA_GLOBALSINDEX)
   end
end


-- disposal function
function lua_State_mt:close()
   C.lua_close(self)
end
lua_State_mt.__gc = lua_State_mt.close

ffi.metatype(lua_State_t, lua_State_mt)

-- END Lua State handling functions
-- BEGIN SnabbSwitch app vm wrapper

-- to wrap pcall()-like functions
-- with return form (bool, ...)
local function stripassert(ok, ...)
   return select(2, assert(ok, ...))
end



local function new_app_vm()
   local vm = lua_State_t()
   vm:add_globals({_shared_packets_fl = _shared_packets_fl})
   assert(vm:load([[
      ffi = require('ffi')
      require('lib.lua.class')
      engine = require('core.app')
      packet = require('core.packet')
      link = require('core.link')
   ]], '[app frame]'))
   assert(vm:pcall())
   return vm
end



-- returns an array of all global function names in the vm
local function get_global_functions(vm)
   return stripassert(vm:load[[
      -- get global function names
      local o = {}
      for k, v in pairs(_G) do
         if type(v) == 'function' then
            o[#o+1] = k
         end
      end
      return o
   ]]:pcall())
end

-- function names that are known to be called as nullary
local known_nullary = {
   pull = true,
   push = true,
   reconfig = false,
   report = true,
   stop = true,
}

-- adds function proxies to the app
local function make_proxies(app, prevglobals)
   prevglobals = prevglobals or {}
   for _, fname in ipairs(prevglobals) do
      prevglobals[fname] = true
   end
   for _, fname in ipairs(get_global_functions(app.vm)) do
      if not prevglobals[fname] then
         if known_nullary[fname] then
            -- optimized, no arguments, pcall()
            app[fname] = function(self)
               assert (self.vm:pcall_null(fname))
            end
         else
            app[fname] = function(self, ...)
               return stripassert(self.vm:pcall(fname, ...))
            end
         end
      end
   end
   return app
end

-- unwraps the link tables inside the vm
local function inject_links(app)
   local vm = app.vm
   vm:load[[
      -- setffitable
      local name, ct, t = ...
      if type(ct) == 'string' then
         ct = ffi.typeof(ct)
      end
      local o = _G[name] or {}
      local memo = {}
      for k,v in pairs(t) do
         if ct and type(v) == 'userdata' then
            memo[v] = memo[v] or ffi.cast(ct, v)
            v = memo[v]
         end
         o[k] = v
      end
      _G[name] = o
   ]]
   C.lua_pushvalue(vm, -1)
   assert(vm:pcall(nil, 'input', 'struct link *', app.input))
   assert(vm:pcall(nil, 'output', 'struct link *', app.output))
end

-- main entry point,
-- construct the 'class' for the named app module
local function sandbox_loader(name)
   return {
      name = name,

      new = function (self, arg)
         local vm = new_app_vm()
         if arg then vm:add_globals(arg) end
         local prevglobals = get_global_functions(vm)
         assert(vm:pcall('require', self.name))
         return make_proxies({
            vm = vm,
            name = self.name,
            zone = self.name,
            inject_links = inject_links,
         }, prevglobals)
      end,
   }
end

-- END SnabbSwitch app vm wrapper

return sandbox_loader
