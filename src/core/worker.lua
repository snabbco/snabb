-- worker.lua - Execute "worker" child processes to execute app networks
-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

-- API:
-- start(name, core)
-- stop(name)
-- status() -> table of { name = <info> }
-- configure(name, config)

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

-- Start a worker process with affinity to a specific CPU core.
-- The child will execute an app network when provided with configure().
function start (name, core)
   local pid = S.fork()
   if pid == 0 then
      -- Lock affinity for this child
      S.sched_setaffinity(0, {core})
      local env = { "SNABB_PROGRAM_LUACODE=require('core.worker').init()",
                    "SNABB_WORKER_NAME="..name,
                    "SNABB_WORKER_PARENT="..S.getppid() }
      -- /proc/$$/exe is a link to the same Snabb executable that we are running
      S.execve(("/proc/%d/exe"):format(S.getpid()), {}, env)
   else
      -- Parent process
      children[name] = { pid = pid, core = core }
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
         core = info.core,
         alive = infop.code == 0
      }
   end
   return status
end

-- Configure a worker process with a new app network.
function configure (name, c)
   -- Ensure "configs" shm counter exists for child to poll
   local child = children[name]
   local child_path = "group/child/"..name
   if not child.configs then
      child.configs = shm.map(child_path.."/configs", {"counter"}, false, true)
   end
   config.save(shm.path(child_path.."/config"), c)
   counter.add(child.configs, 1)
end

--------------------------------------------------------------
-- Worker (child) process code
--------------------------------------------------------------

-- Initialize the worker by attaching to relevant shared memory
-- objects and entering the main engine loop.
function init (name, parentpid)
   local name = assert(lib.getenv("SNABB_WORKER_NAME"))
   local parent = assert(lib.getenv("SNABB_WORKER_PARENT"))
   print(("Starting worker %s for parent %d"):format(name, parent))

   -- Create "group" alias to the shared group folder in the parent process
   shm.alias("group", "/"..parent.."/group")

   -- Wait for parent to provide an initial configuration
   local warned
   while not shm.exists("group/"..name.."/configs.counter") do
      if not warned then
         print("waiting for configuration...")
         warned = true
         S.nanosleep(0.001)
      end
   end

   -- Map the counter for how many times our configuration has been updated.
   -- This provides an efficient way to poll for updates.
   local configs = shm.map("group/"..name.."/configs", "counter")

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
      start(w, 0)
   end
   print("Worker status:")
   for w, s in pairs(status()) do
      print(("  worker %s: pid=%s core=%s alive=%s"):format(
            w, s.pid, s.core, s.alive))
   end
   print("Stopping children")
   for _, w in ipairs(workers) do
      stop(w)
   end
   S.nanosleep(1)
   print("Worker status:")
   for w, s in pairs(status()) do
      print(("  worker %s: pid=%s core=%s alive=%s"):format(
            w, s.pid, s.core, s.alive))
   end
   print("selftest: done")
end

