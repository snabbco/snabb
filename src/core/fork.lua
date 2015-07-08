module(..., package.seeall)
local S = require('syscall')


local function eachmodule(fname, ...)
   for modname, module in pairs(package.loaded) do
      if type(module) == 'table' and rawget(module, fname) then
         module[fname](...)
      end
   end
end


local hasForked = false
local procname = '_master_'

function spawn(name, f, ...)
   if not hasForked then
      hasForked = true
      eachmodule('prefork')
   end

   local childpid = S.fork()
   if childpid == 0 then
      procname = name
      eachmodule('postfork')
      f(...)
      eachmodule('endfork')
      os.exit()
   end

   return childpid
end


function get_procname()
   return procname
end


function wait()
   local pid = assert(S.waitpid(-1, 0))
   eachmodule('reapfork', pid)
   return pid
end
