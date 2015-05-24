
local statebox = require ('lib.lua.statebox')
local freelist = require ('core.freelist')

-- to wrap pcall()-like functions
-- with return form (bool, ...)
local function stripassert(ok, ...)
   return select(2, assert(ok, ...))
end


-- shallow table copy
local function copy(dst, src, ...)
   if not src then return dst end
   for k, v in pairs(src) do
      dst[k] = v
   end
   return copy(dst, ...)
end


-- returns an array of all global function names in appbox
local function get_global_functions(appbox)
   return stripassert(appbox:load[[
      local o = {}
      for k, v in pairs(_G) do
         if type(v) == 'function' then
            o[#o+1] = k
         end
      end
      return o
   ]]:pcall())
end


-- returns a table with the global values of the given names
local function pull_known_names(appbox, ...)
   return stripassert(appbox:load[[
      local o = {}
      for i = 1, select('#', ...) do
         local name = select(i, ...)
         o[name] = _G[name]
      end
      return o
   ]]:pcall(nil, ...))
end


-- creates the LuaState sandbox
-- and loads with the SnS app
-- returns a Lua table with a proxy for
-- each global function and some values (name, zone)
-- defined in the app
function new_app(class, args)
   local appbox = assert(statebox[[
      -- minimal libraries
      ffi = require ('ffi')
      freelist = require ('core.freelist')
      engine = require ('core.app')
      packet = require ('core.packet')
      link = require ('core.link')

      -- sets a table of FFI objects
      -- used for injecting in/out links
      local prevcts = {}
      function setffitable(name, ct, t)
         if not t then return end
         if ct and type(ct) == 'string' then
            prevcts[ct] = prevcts[ct] or ffi.typeof(ct)
            ct = prevcts[ct]
         end
         local o = _G[name] or {}
         for k,v in pairs(t) do
            if ct and type(v) == 'userdata' then
               v = ffi.cast(ct, v)
            end
            o[k] = v
         end
         _G[name] = o
      end

      -- loads the app within the sandbox
      -- appname is the dotted name, loaded with require()
      -- args will be copied to _G
      -- profilemod (optional) like '-jp=...' commandline parameter
      function loadapp(appname, args, profilemode)
         if args then
            for k, v in pairs(args) do
               _G[k] = v
            end
         end
         if profilemode then
            require("jit.p").start(profilemode)
         end
         require (appname)
         if profilemode then
            local prevstop = stop
            stop = function ()
               if prevstop then prevstop() end
               print ('profile: ', appname)
               require('jit.p').stop()
            end
         end
      end
   ]])

   -- load initial chunk
   assert(appbox:pcall())
   -- insert shared freelists
   require('core.packet').init()
   freelist.share_lists(function(t)
      assert(appbox:load "freelist.receive_shared(...)":pcall(nil, t))
   end)

   -- jumpstart packet module
   assert(appbox:load "packet.init()": pcall())

   -- load app module
   local prevglobals = get_global_functions(appbox)
   assert(appbox:pcall('loadapp', class.appname, args, '4vl'))

   -- set proxy values
   local app = copy({
      name = class.appname,
      zone = class.appname,
      appbox = appbox,
   }, pull_known_names(appbox, 'name', 'zone'))

   -- set proxy functions
   for _, fname in ipairs(prevglobals) do
      prevglobals[fname] = true
   end
   for _, fname in ipairs(get_global_functions(appbox)) do
      if not prevglobals[fname] then
         app[fname] = function(self, ...)
            return stripassert(self.appbox:pcall(fname, ...))
         end
      end
   end

   -- use the relink function to inject links into the sandbox
   local prevrelink = app.relink
   app.relink = function(self)
      self.appbox:pcall('setffitable', 'input', 'struct link *', self.input)
      self.appbox:pcall('setffitable', 'output', 'struct link *', self.output)
      if prevrelink then
         return prevrelink(self)
      end
   end

   return app
end


-- main entry point
-- the 'class' is just something to call :new() on
function make_app_class(appname)
   return {
      appname = appname,
      new = new_app,
   }
end


-- return the loader function
return make_app_class
