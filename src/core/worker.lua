-- worker.lua - Execute "worker" child processes to execute app networks
-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- API:
-- start(name, core)
-- stop(name)
-- status() -> table of { name = <info> }
-- configure(name, config)

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
   if pid ~= 0 then
      -- Child (worker) process
      init(name, core, S.getppid())
   else
      -- Parent process
      children[name] = { pid = pid, core = core }
   end
end

-- Terminate a child process
function stop (name)
   S.kill(child(name), 'kill')
end

-- Return information about all worker processes in a table.
function status ()
   local status = {}
   for name, info in pairs(children) do
      status[name] = {
         pid = info.pid,
         alive = (S.kill(info.pid, 0) == 0)
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
function init (name, core, parentpid)
   local name = parameters[1]
   local parent = num(parameters[2])
   local core = num(parameters[3])
   print(("Starting worker %s on core %d for parent %d"):format(name, core, parent))

   -- Setup affinity
   if core then S.sched_setaffinity(0, {core}) end

   -- Create "group" alias to the shared group folder in the parent process
   shm.alias("group", "/"..parent.."/group")

   -- Wait for parent to provide an initial configuration
   local warned
   while not shm.exists("group/"..name.."/configs.counter") do
      if not warned then
         print("waiting for configuration...")
         warned = true
         C.usleep(1000)
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


