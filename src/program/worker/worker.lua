-- worker.lua - Snabb engine worker process to execute an app network
-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local lib = require("core.lib")
local usage = require("program.worker.README_inc")
local shm = require("core.shm")
local ffi = require("ffi")
local C   = ffi.C
local S = require("syscall")

function run (parameters)
   if #parameters ~= 3 then
      print(usage)
      os.exit(1)
   end
   -- Parse a numeric parameter
   local function num (string)
      if string:match("^[0-9]+$") then
         return tonumber(string)
      else
         print("bad number: " .. string)
         main.exit(1)
      end
   end
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
   local update = function () return current_config ~= counter.read(configs) end
   while true do
      if update() then
         -- note: read counter _before_ config file to avoid a race
         current_config = counter.read(configs)
         local c = config.readfile(shm.path("group/config/"..name))
         engine.configure(c)
      end
      -- Run until next update
      engine.main({done = update, no_report = true})
   end
end

