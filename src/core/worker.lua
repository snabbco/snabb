-- worker.lua - Execute "worker" child processes to execute app networks
-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

-- API:
-- start(name, luacode)
-- stop(name)
-- status() -> table of { name = <info> }

local lib = require("core.lib")
local shm = require("core.shm")
local S = require("syscall")

--------------------------------------------------------------
-- Master (parent) process code
--------------------------------------------------------------

local children = {}

local function child (name)
   return children[name] or error("no such child: " .. name)
end

-- Start a named worker to execute the given Lua code (a string).
function start (name, luacode)
   local pid = S.fork()
   if pid == 0 then
      -- First we perform some initialization functions and then we
      -- restart the process with execv().
      
      -- Terminate automatically when the parent dies.
      --
      -- XXX This prctl setting needs to survive execve(). The Linux
      -- execve(2) page seems to say that it will provided that the
      -- binary being executed is not setuid or setgid. This may or
      -- may not be adequate.
      S.prctl("set_pdeathsig", "hup")
      -- Symlink the shm "group" folder to be shared via the parent process.
      shm.alias("group", "/"..S.getppid().."/group")
      -- Save the code we want to run in the environment.
      S.setenv("SNABB_PROGRAM_LUACODE", luacode, true)
      -- Restart the process with execve().
      -- /proc/$$/exe is a link to the same Snabb executable that we are running
      local env = {}
      for key, value in pairs(S.environ()) do
         table.insert(env, key.."="..value)
      end
      S.execve(("/proc/%d/exe"):format(S.getpid()), {}, env)
   else
      -- Parent process
      children[name] = { pid = pid }
   end
end

-- Terminate a child process
function stop (name)
   S.kill(child(name).pid, 'kill')
end

-- Return information about all worker processes in a table.
function status ()
   local status = {}
   for name, info in pairs(children) do
      local infop = S.waitid("pid", info.pid, "nohang, exited")
      status[name] = {
         pid = info.pid,
         alive = infop and infop.code == 0 or false
      }
   end
   return status
end

--------------------------------------------------------------
-- Worker (child) process code
--------------------------------------------------------------

-- Initialize the worker by attaching to relevant shared memory
-- objects and entering the main engine loop.
function init ()
   local name = assert(lib.getenv("SNABB_WORKER_NAME"))
   local parent = assert(lib.getenv("SNABB_WORKER_PARENT"))
   print(("Starting worker %s for parent %d"):format(name, parent))

   -- Create "group" alias to the shared group folder in the parent process
   shm.alias("group", "/"..parent.."/group")

   -- Run the engine with continuous configuration updates
   local current_config
   local child_path = "group/config/..name"
   local update = function () return current_config ~= counter.read(configs) end
   while true do
      if update() then
         -- note: read counter _before_ config file to avoid a race
         current_config = counter.read(configs)
         local c = config.load(shm.path(child_path.."/config"))
         engine.configure(c)
      end
      -- Run until next update
      engine.main({done = update, no_report = true})
   end
end

function selftest ()
   print("selftest: worker")
   -- XXX This selftest function is very basic. Should be expanded to
   --     run app networks in child processes and ensure that they work.
   local workers = { "w1", "w2", "w3" }
   print("Starting children")
   for _, w in ipairs(workers) do
      start(w, ([[ print("  (hello world from worker %s. entering infinite loop...)")
                   while true do end -- infinite loop ]]):format(w))
   end
   print("Worker status:")
   for w, s in pairs(status()) do
      print(("  worker %s: pid=%s alive=%s"):format(
            w, s.pid, s.alive))
   end
   S.nanosleep(0.1)
   print("Stopping children")
   for _, w in ipairs(workers) do
      stop(w)
   end
   S.nanosleep(0.1)
   print("Worker status:")
   for w, s in pairs(status()) do
      print(("  worker %s: pid=%s alive=%s"):format(
            w, s.pid, s.alive))
   end
   print("selftest: done")
end

