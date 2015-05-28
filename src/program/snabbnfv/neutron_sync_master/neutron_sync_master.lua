module(..., package.seeall)

local lib  = require("core.lib")
local syscall = require("syscall")
local usage = require("program.snabbnfv.neutron_sync_master.README_inc")
local script = require("program.snabbnfv.neutron_sync_master.neutron_sync_master_sh_inc")

local long_opts = {
   user                 = "u",
   password             = "p",
   ["mysql-host"]       = "m",
   ["mysql-port"]       = "M",
   ["neutron-database"] = "D",
   ["dump-path"]        = "d",
   tables               = "t",
   ["listen-address"]   = "l",
   ["listen-port"]      = "L",
   interval             = "i",
   help                 = "h"
}

function run (args)
   local conf               = {
      ["DB_USER"]           = os.getenv("DB_USER"),
      ["DB_PASSWORD"]       = os.getenv("DB_PASSWORD"),
      ["DB_DUMP_PATH"]      = os.getenv("DB_DUMP_PATH"),
      ["DB_HOST"]           = os.getenv("DB_HOST") or "localhost",
      ["DB_PORT"]           = os.getenv("DB_PORT") or "3306",
      ["DB_NEUTRON"]        = os.getenv("DB_NEUTRON") or "neutron_ml2",
      ["DB_NEUTRON_TABLES"] = os.getenv("DB_NEUTRON_TABLES") or "networks ports ml2_network_segments ml2_port_bindings securitygroups securitygrouprules securitygroupportbindings",
      ["SYNC_LISTEN_HOST"]  = os.getenv("SYNC_LISTEN_HOST") or "127.0.0.1",
      ["SYNC_LISTEN_PORT"]  = os.getenv("SYNC_LISTEN_PORT") or "9418",
      ["SYNC_INTERVAL"]     = os.getenv("SYNC_INTERVAL") or "1"
   }
   local opt = {}
   function opt.u (arg) conf["DB_USER"]           = arg end
   function opt.p (arg) conf["DB_PASSWORD"]       = arg end
   function opt.d (arg) conf["DB_DUMP_PATH"]      = arg end
   function opt.t (arg) conf["DB_NEUTRON_TABLES"] = arg end
   function opt.D (arg) conf["DB_NEUTRON"]        = arg end
   function opt.m (arg) conf["DB_HOST"]           = arg end
   function opt.M (arg) conf["DB_PORT"]           = arg end
   function opt.l (arg) conf["SYNC_LISTEN_HOST"]  = arg end
   function opt.L (arg) conf["SYNC_LISTEN_PORT"]  = arg end
   function opt.i (arg) conf["SYNC_INTERVAL"]     = arg end
   function opt.h (arg) print(usage) main.exit(1)       end
   args = lib.dogetopt(args, opt, "u:p:t:i:d:m:M:l:L:D:h", long_opts)
   local env = {}
   for key, value in pairs(conf) do
      table.insert(env, key.."="..value) 
   end
   syscall.execve("/bin/bash", {"/bin/bash", "-c", script}, env)
end
