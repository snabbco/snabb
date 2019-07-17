-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local lib = require("core.lib")
local shm = require("core.shm")
local S = require("syscall")
local usage = require("program.shm.README_inc")

-- We must load any modules that register abstract shm types that we may
-- wish to inspect.
require("core.packet")
local counter = require("core.counter")
require("core.histogram")
require("lib.interlink")

local long_opts = {
   help = "h"
}

function run (args)
   local opt = {}
   local object = nil
   function opt.h (arg) print(usage) main.exit(1) end
   args = lib.dogetopt(args, opt, "h", long_opts)

   if #args ~= 1 then print(usage) main.exit(1) end
   local path = args[1]

   -- Hacky way to accept an arbitrary relative or absolute path
   if path:sub(1,1) == '/' then
      shm.root = lib.dirname(path)
      path = path:sub(#shm.root+1)
   else
      shm.root = S.getcwd()
   end

   -- Open path as SHM frame
   local frame = shm.open_frame(path)

   -- Frame fields to ignore
   local ignored = {path=true, specs=true, readonly=true}

   -- Compute sorted array of members to print
   local sorted = {}
   for name, _ in pairs(frame) do
      if not ignored[name] then table.insert(sorted, name) end
   end
   table.sort(sorted)

   -- Convert dtime counter to human-readable date/time string if it exists
   if frame.dtime then
      frame.dtime = os.date("%c", tonumber(counter.read(frame.dtime)))
   end

   -- Print SHM frame objects
   local name_max = 40
   for _, name in ipairs(sorted) do
      print(name..": "..tostring(frame[name]))
   end
end
