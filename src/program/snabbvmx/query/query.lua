module(..., package.seeall)

local S = require("syscall")
local counter = require("core.counter")
local ffi = require("ffi")
local lib = require("core.lib")
local ipv4 = require("lib.protocol.ipv4")
local ethernet = require("lib.protocol.ethernet")
local lwaftr = require("apps.lwaftr.lwaftr")
local lwtypes = require("apps.lwaftr.lwtypes")
local lwutil = require("apps.lwaftr.lwutil")
local lwcounter = require("apps.lwaftr.lwcounter")
local shm = require("core.shm")
local top = require("program.top.top")

local select_snabb_instance = top.select_snabb_instance
local keys = lwutil.keys

local macaddress_t = ffi.typeof[[
struct { uint8_t ether[6]; }
]]

-- Get the counter dir from the code.
local lwaftr_counters_rel_dir = lwcounter.counters_dir

function show_usage (code)
   print(require("program.lwaftr.query.README_inc"))
   main.exit(code)
end

local function sort (t)
   table.sort(t)
   return t
end

local function is_counter_name (name)
   return lwaftr.counter_names[name] ~= nil
end


function parse_args (raw_args)
   local handlers = {}
   function handlers.h() show_usage(0) end
   local args = lib.dogetopt(raw_args, handlers, "h",
                             { help="h" })
   if #args > 0 then show_usage(1) end
   return nil
end

local function read_lwaftr_counters (tree)
   local ret = {}
   local cnt, cnt_path, value
   local counters_path = "/" .. tree .. "/" .. lwaftr_counters_rel_dir
   local counters = shm.children(counters_path)
   for _, name in ipairs(counters) do
      cnt_path = counters_path .. name
      cnt = counter.open(cnt_path, 'readonly')
      value = tonumber(counter.read(cnt))
      name = name:gsub(".counter$", "")
      ret[name] = value
    end
   return ret
end

local function read_apps_counters (tree, app_name)
   local ret = {}
   local cnt, cnt_path, value
   local counters_path = "/" .. tree .. "/apps/" .. app_name .. "/"
   local counters = shm.children(counters_path)
   for _, name in ipairs(counters) do
      cnt_path = counters_path .. name
      cnt = counter.open(cnt_path, 'readonly')
      value = tonumber(counter.read(cnt))
      name = name:gsub(".counter$", "")
      ret[name] = value
    end
   return ret
end

local function print_counter (name, value)
   print(("      <%s>%d</%s>"):format(name, value, name))
end

-- TODO: Refactor to a general common purpose library.
local function file_exists(path)
  local stat = S.stat(path)
  return stat and stat.isreg
end

function print_next_hop (pid, name)
  local next_hop_mac = "/" .. pid .. "/" .. name
  if file_exists(shm.root .. next_hop_mac) then
    local nh = shm.open(next_hop_mac, macaddress_t, "readonly")
    print(("    <%s>%s</%s>"):format(name, ethernet:ntop(nh.ether), name))
  end
end

function print_monitor (pid)
  local path = "/" .. pid .. "/v4v6_mirror"
  if file_exists(shm.root .. path) then
    local ipv4_address = shm.open(path, "struct { uint32_t ipv4; }", "readonly")
    print(("    <%s>%s</%s>"):format("monitor", ipv4:ntop(ipv4_address), "monitor"))
  end
end

function print_apps_counters (tree)
  local apps_path = "/" .. tree .. "/apps"
   local apps = shm.children(apps_path)
   for _, app_name in ipairs(apps) do
     print(("    <%s>"):format(app_name))
     -- Open, read and print whatever counters are in that directory.
     local counters = read_apps_counters(tree, app_name)
     for _, name in ipairs(sort(keys(counters))) do
       local value = counters[name]
       print_counter(name, value)
     end
     print(("    </%s>"):format(app_name))
   end
end

function run (raw_args)
   parse_args(raw_args)
   print("<snabb>")
   for _, pid in ipairs(shm.children("/")) do
      if shm.exists("/"..pid.."/nic/id") then
         local lwaftr_id = shm.open("/"..pid.."/nic/id", lwtypes.lwaftr_id_type)
         local instance_id = ffi.string(lwaftr_id.value)
         if instance_id then
           print("  <instance>")
           print(("   <id>%s</id>"):format(instance_id))
           print(("   <pid>%d</pid>"):format(pid))
           print_next_hop(pid, "next_hop_mac_v4")
           print_next_hop(pid, "next_hop_mac_v6")
           print_monitor(pid)
           print_apps_counters(pid)
           print("  </instance>")
         end
      end
   end
   print("</snabb>")
end
