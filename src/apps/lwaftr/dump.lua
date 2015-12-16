module(..., package.seeall)

local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local ipv4 = require("lib.protocol.ipv4")

local CONF_FILE_DUMP = "/tmp/lwaftr-%s.conf"
local BINDING_TABLE_FILE_DUMP = "/tmp/binding-%s.table"

local function set(...)
   local result = {}
   for _, v in ipairs({...}) do
      result[v] = true
   end
   return result
end

local function write_to_file(filename, content)
   local fd = io.open(filename, "wt")
   fd:write(content)
   fd:close()
end

-- 'ip' is in host bit order, convert to network bit order
local function ipv4number_to_str(ip)
   local a = bit.band(ip, 0xff)
   local b = bit.band(bit.rshift(ip, 8), 0xff)
   local c = bit.band(bit.rshift(ip, 16), 0xff)
   local d = bit.rshift(ip, 24)
   return ("%d.%d.%d.%d"):format(a, b, c, d)
end

function dump_configuration(lwstate)
   print("Dump configuration")
   local result = {}
   local etharr = set('aftr_mac_b4_side',  'aftr_mac_inet_side', 'b4_mac',  'inet_mac')
   local ipv4arr = set('aftr_ipv4_ip')
   local ipv6arr = set('aftr_ipv6_ip')
   local val
   for _, k in ipairs(lwstate.conf_keys) do
      local v = lwstate[k]
      if etharr[k] then
         val = ("ethernet:pton('%s')"):format(ethernet:ntop(v))
      elseif ipv4arr[k] then
         val = ("ipv4:pton('%s')"):format(ipv4:ntop(v))
      elseif ipv6arr[k] then
         val = ("ipv6:pton('%s')"):format(ipv6:ntop(v))
      elseif type(v) == "bool" then
         val = v and "true" or "false"
      elseif k == "binding_table" then
         val = "bt.get_binding_table()"
      else
         val = lwstate[k]
      end
      table.insert(result, ("%s = %s"):format(k, val))
   end
   local filename = (CONF_FILE_DUMP):format(os.date("%Y-%m-%d-%H:%M:%S"))
   local content = table.concat(result, ",\n")
   write_to_file(filename, content)
   print(("Configuration written to %s"):format(filename))
end

function dump_binding_table(lwstate)
   print("Dump binding table")
   local content = {}
   local function write(str)
      table.insert(content, str)
   end
   local function dump()
      return table.concat(content, "\n")
   end
   local function format_entry(entry)
      local v6, v4, port_start, port_end, br_v6 = entry[1], entry[2], entry[3], entry[4], entry[5]
      local result = {}
      table.insert(result, ("'%s'"):format(ipv6:ntop(v6)))
      table.insert(result, ("'%s'"):format(ipv4number_to_str(v4)))
      table.insert(result, port_start)
      table.insert(result, port_end)
      if br_v6 then
         table.insert(result, ("'%s'"):format(ipv6:ntop(br_v6)))
      end
      return table.concat(result, ",")
   end
   -- Write entries to content
   write("{")
   for _, entry in ipairs(lwstate.binding_table) do
      write(("\t{%s},"):format(format_entry(entry)))
   end
   write("}")
   -- Dump content to file
   local filename = (BINDING_TABLE_FILE_DUMP):format(os.date("%Y-%m-%d-%H:%M:%S"))
   write_to_file(filename, dump())
   print(("Binding table written to %s"):format(filename))
end
