local ffi = require('ffi')
local C = ffi.C

ffi.cdef [[
   /*
    * copied from lua.h
    */

   typedef struct lua_State lua_State;
   typedef void * (*lua_Alloc) (void *ud, void *ptr, size_t osize, size_t nsize);
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

   // thread status; 0 is OK
   enum {
      LUA_YIELD = 1,
      LUA_ERRRUN,
      LUA_ERRSYNTAX,
      LUA_ERRMEM,
      LUA_ERRERR,
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
   int lua_resume (lua_State *L, int narg);
   void lua_settable (lua_State *L, int index);
   void lua_settop (lua_State *L, int index);
   int lua_status (lua_State *L);
   int lua_toboolean (lua_State *L, int index);
   const char *lua_tolstring (lua_State *L, int index, size_t *len);
   lua_Number lua_tonumber (lua_State *L, int index);
   int lua_type (lua_State *L, int index);

   int luaL_loadbuffer (lua_State *L, const char *buff, size_t sz, const char *name);
   lua_State *luaL_newstate (void);
   void luaL_openlibs (lua_State *L);
]]


ffi.cdef [[
   // our sandbox structure.  currently it's just a Lua State
   struct statebox {
      lua_State *L;
   };
]]

local statebox = {}
statebox.__index = statebox

local statebox_t = ffi.typeof('struct statebox')

-- pushes several values into the given LuaState stack
-- handles only symple values: nil, boolean, numbers (double floats),
-- strings, tables (only key/values of known types), userdata and
-- cdata, which are pushed as lightuserdata values
local function push_values(L, ...)
   local narg = select('#', ...)
   local prevtop = C.lua_gettop(L)
   for i = 1, narg do
      local v = select(i, ...)
      local typ = type(v)
      if typ == 'nil' then
         C.lua_pushnil(L)
      elseif typ == 'boolean' then
         C.lua_pushboolean(L, v)
      elseif typ == 'number' then
         C.lua_pushnumber(L, v)
      elseif typ == 'string' then
         C.lua_pushlstring(L, v, #v)
      elseif typ == 'table' then
         C.lua_createtable(L, 0, 0)
         for k1, v1 in pairs(v) do
            push_values(L, k1, v1)
            C.lua_settable(L, -3)
         end
      elseif typ == 'userdata' or typ == 'cdata' then
         C.lua_pushlightuserdata(L, v)
      end
   end

   return C.lua_gettop(L) - prevtop
end

-- returns a variable number of values from the stack
-- of a Lua State, optinally pops those values.
-- L : Lua State we want to read
-- num (optional): number of values to read.  defaults to all values
-- keep (optional): boolean flag, if true, keeps the values in the stack
--  if false, removes the values it reads.
local pv_sz = ffi.new('size_t[?]', 1)
local function pull_values(L, num, keep)
   local narg = C.lua_gettop(L)
   num = num or narg
   local o = {}
   for i = narg-num+1, narg do
      local typ, v = C.lua_type(L, i), nil
      if typ == C.LUA_TNIL then
         v = nil
      elseif typ == C.LUA_TBOOLEAN then
         v = C.lua_toboolean(L, i) ~= 0
      elseif typ == C.LUA_TNUMBER then
         v = C.lua_tonumber(L, i)
      elseif typ == C.LUA_TSTRING then
         local buf = C.lua_tolstring(L, i, pv_sz)
         v = ffi.string(buf, pv_sz[0])
      elseif typ == C.LUA_TTABLE then
         v = {}
         C.lua_pushnil(L)
         while C.lua_next(L, i) ~= 0 do
            local k1, v1 = pull_values(L, 2, true)
            v[k1] = v1
            C.lua_settop(L, -2)
         end
      end
      o[i-narg+num] = v
   end
   if not keep then
      C.lua_settop(L, narg-num)
   end
   return unpack(o)
end

-- FFI object constructor.
-- creates the Lua State and loads standard libraries.
-- optionally compiles the given Lua code chunk and
-- leaves the resultant function in the stack.
function statebox:__new(code)
   local box = ffi.new(statebox_t)
   return assert(box:init():load(code, '[startcode]'))
end

-- object initializer
-- creates the Lua State and loads standard libraries.
-- signals an error on failure to create the State
function statebox:init()
   if self.L ~= nil then return self end

   self.L = C.luaL_newstate()
   assert(self.L ~= nil, "Couldn't allocate new LuaState")

   C.luaL_openlibs(self.L)
   return self
end

-- compiles a chunk of code and leaves the resultant function in the stack.
-- returns self or false and an error message
function statebox:load(code, name)
   if self.L == nil then return false, "Can't load code on a closed statebox" end
   if not code then return self end

   if C.luaL_loadbuffer(self.L, code, #code, name) ~= 0 then
      local err = ffi.string(C.lua_tolstring(self.L, -1, nil))
      self:close()
      return false, "Error loading startcode: "..tostring(err)
   end

   return self
end

-- calls a function in the Lua State.
-- the first argument should be either:
--   - the name of a function in the global environment
--   - nil to call a function in the top of the stack
-- the rest of the arguments are sent to the function
-- according to the limitations of push_values().
-- returns (true, result values) if successful or
-- (false, error) if any error is raised (similar to standard pcall())
function statebox:pcall(fname, ...)
   if self.L == nil then return false, "Can't call closed statebox" end

   if fname ~= nil then
      C.lua_getfield(self.L, C.LUA_GLOBALSINDEX, fname)
   end

   local nargs, err = push_values(self.L, ...)
   if not nargs then return nargs, err end

   if C.lua_pcall(self.L, nargs, C.LUA_MULTRET, 0) ~= 0 then
      local err = ffi.string(C.lua_tolstring(self.L, -1, nil))
      C.lua_settop(self.L, 0)
      return false, err
   end

   return true, pull_values(self.L)
end

-- resumes the Lua State as a coroutine.
-- if there's a function in the top of the stack it's popped
-- and called with the given parameters (like :pcall(nil, ...))
-- if it finishes successfully or calls coroutine.yield(),
-- this will return (true, result values).
-- if the state has yield()ed, subsequent resume() calls will
-- continue the coroutine operation.
-- if the coroutine has finished or raised an error, it will
-- be an error to call :resume() again.
-- returns (false, error) on any failure
function statebox:resume(...)
   if self.L == nil then return false, "Can't resume closed statebox" end

   if C.lua_status(self.L) ~= 1 and C.lua_type(self.L, -1) ~= C.LUA_TFUNCTION then
      return false, "Need a function or suspended thread"
   end

   local nargs, err = push_values(self.L, ...)
   if not nargs then return nargs, err end

   local ret = C.lua_resume(self.L, nargs)
   if ret == 0 or ret == C.LUA_YIELD then
      return true, pull_values(self.L)
   end
   return false, ffi.string(C.lua_tolstring(self.L, -1, nil))
end

-- disposes the Lua state.
-- calling :init() again can reopen the box
function statebox:close()
   if self.L ~= nil then
      C.lua_close(self.L)
      self.L = nil
   end
end

-- garbage collection hook
function statebox:__gc()
   self:close()
end

-- returns the type as the whole module,
-- can be used as FFI type and constructor
ffi.metatype(statebox_t, statebox)
return statebox_t
