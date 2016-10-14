module(..., package.seeall)

local S = require("syscall")
local counter = require("core.counter")
local ffi = require("ffi")
local lib = require("core.lib")
local ipv4 = require("lib.protocol.ipv4")
local ethernet = require("lib.protocol.ethernet")
local lwtypes = require("apps.lwaftr.lwtypes")
local lwutil = require("apps.lwaftr.lwutil")
local shm = require("core.shm")

local keys = lwutil.keys

local macaddress_t = ffi.typeof[[
struct { uint8_t ether[6]; }
]]

local function show_usage (code)
   print(require("program.snabbvmx.query.README_inc"))
   main.exit(code)
end

local function sort (t)
   table.sort(t)
   return t
end

local function parse_args (raw_args)
   local handlers = {}
   function handlers.h() show_usage(0) end
   local args = lib.dogetopt(raw_args, handlers, "h",
                             { help="h" })
   if #args > 0 then show_usage(1) end
   return nil
end

local function read_counters (tree, app_name)
   local ret = {}
   local cnt, cnt_path, value
   local counters_path = "/" .. tree .. "/" .. app_name .. "/"
   local counters = shm.children(counters_path)
   for _, name in ipairs(counters) do
      cnt_path = counters_path .. name
      if string.match(cnt_path, ".counter") then
        cnt = counter.open(cnt_path, 'readonly')
        value = tonumber(counter.read(cnt))
        name = name:gsub(".counter$", "")
        ret[name] = value
      end
    end
   return ret
end

-- TODO: Refactor to a general common purpose library.
local function file_exists(path)
  local stat = S.stat(path)
  return stat and stat.isreg
end

local function print_next_hop (pid, name)
  local next_hop_mac = "/" .. pid .. "/" .. name
  if file_exists(shm.root .. next_hop_mac) then
    local nh = shm.open(next_hop_mac, macaddress_t, "readonly")
    print(("   <%s>%s</%s>"):format(name, ethernet:ntop(nh.ether), name))
  end
end

local function print_monitor (pid)
  local path = "/" .. pid .. "/v4v6_mirror"
  if file_exists(shm.root .. path) then
    local ipv4_address = shm.open(path, "struct { uint32_t ipv4; }", "readonly")
    print(("   <%s>%s</%s>"):format("monitor", ipv4:ntop(ipv4_address), "monitor"))
  end
end

local function print_counters (pid, dir)
  local apps_path = "/" .. pid .. "/" .. dir
  local apps
  print(("   <%s>"):format(dir))
  if dir == "engine" then
    -- Open, read and print whatever counters are in that directory.
    local counters = read_counters(pid, dir)
    for _, name in ipairs(sort(keys(counters))) do
      local value = counters[name]
      print(("     <%s>%d</%s>"):format(name, value, name))
    end
  else
    apps = shm.children(apps_path)
    for _, app_name in ipairs(apps) do
      local sanitized_name = string.gsub(app_name, "[ >:]", "-")
      if (string.find(sanitized_name, "^[0-9]")) then
        sanitized_name = "_" .. sanitized_name
      end
      print(("     <%s>"):format(sanitized_name))
      -- Open, read and print whatever counters are in that directory.
      local counters = read_counters(pid .. "/" .. dir, app_name)
      for _, name in ipairs(sort(keys(counters))) do
        local value = counters[name]
        print(("       <%s>%d</%s>"):format(name, value, name))
      end
      print(("     </%s>"):format(sanitized_name))
    end
  end
  print(("   </%s>"):format(dir))
end

function run (raw_args)
   parse_args(raw_args)
   print("<snabb>")
   local pids = {}
   local pids_name = {}
   for _, pid in ipairs(shm.children("/")) do
     if shm.exists("/"..pid.."/nic/id") then
       local lwaftr_id = shm.open("/"..pid.."/nic/id", lwtypes.lwaftr_id_type)
       local instance_id_name = ffi.string(lwaftr_id.value)
       local instance_id = instance_id_name and instance_id_name:match("(%d+)")
       if instance_id then
         pids[instance_id] = pid
         pids_name[instance_id] = instance_id_name
       end
     end
   end
   for _, instance_id in ipairs(sort(keys(pids))) do
     local pid = pids[instance_id]
     print("  <instance>")
     print(("   <id>%d</id>"):format(instance_id))
     print(("   <name>%s</name>"):format(pids_name[instance_id]))
     print(("   <pid>%d</pid>"):format(pid))
     print_next_hop(pid, "next_hop_mac_v4")
     print_next_hop(pid, "next_hop_mac_v6")
     print_monitor(pid)
     print_counters(pid, "engine")
     print_counters(pid, "pci")
     print_counters(pid, "apps")
     print_counters(pid, "links")
     print("  </instance>")
   end
   print("</snabb>")
end
