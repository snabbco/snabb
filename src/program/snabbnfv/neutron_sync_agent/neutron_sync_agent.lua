module(..., package.seeall)

local lib  = require("core.lib")
local syscall = require("syscall")
local usage = require("program.snabbnfv.neutron_sync_agent.README_inc")
local script = require("program.snabbnfv.neutron_sync_agent.neutron_sync_agent_sh_inc")

local long_opts = {
   ["neutron-dir"] = "d",
   ["snabb-dir"]   = "s",
   ["sync-host"]   = "h",
   ["sync-path"]   = "p",
   ["interval"]    = "i",
   ["help"]        = "h"
}

function run (args)
   local conf = {
      ["NEUTRON_DIR"]   = os.getenv("NEUTRON_DIR"),
      ["SNABB_DIR"]     = os.getenv("SNABB_DIR"),
      ["NEUTRON2SNABB"] = os.getenv("NEUTRON2SNABB"),
      ["SYNC_HOST"]     = os.getenv("SYNC_HOST"),
      ["SYNC_PATH"]     = os.getenv("SYNC_PATH"),
      ["SYNC_INTERVAL"] = os.getenv("SYNC_INTERVAL")
   }
   local opt = {}
   function opt.d (arg) conf["NEUTRON_DIR"]   = arg end
   function opt.s (arg) conf["SNABB_DIR"]     = arg end
   function opt.h (arg) conf["SYNC_HOST"]     = arg end
   function opt.p (arg) conf["SYNC_PATH"]     = arg end
   function opt.i (arg) conf["SYNC_INTERVAL"] = arg end
   function opt.h (arg) print(usage) main.exit(1)   end
   args = lib.dogetopt(args, opt, "d:s:h:p:i:h", long_opts)
   local env = {}
   for key, value in pairs(conf) do
      table.insert(env, key.."="..value) 
   end
   syscall.execve("/bin/bash", {"/bin/bash", "-c", script}, env)
end
