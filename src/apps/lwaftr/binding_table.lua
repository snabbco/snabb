module(..., package.seeall)

local ffi = require("ffi")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")

-- TODO: rewrite this after netconf integration
local function read_binding_table(bt_file)
  local input = io.open(bt_file)
  local entries = input:read('*a')
  local full_bt = 'return ' .. entries
  return assert(loadstring(full_bt))()
end

local machine_friendly_binding_table

-- b4_v6 is for the B4, br_v6 is for the border router (lwAFTR)
local function pton_binding_table(bt)
   local pbt = {}
   for _, v in ipairs(bt) do
      local b4_v6 = ipv6:pton(v[1])
      local pv4 = ffi.cast("uint32_t*", ipv4:pton(v[2]))[0]
      local pentry
      if v[5] then
         local br_v6 = ipv6:pton(v[5])
         pentry = {b4_v6, pv4, v[3], v[4], br_v6}
      else
         pentry = {b4_v6, pv4, v[3], v[4]}
      end
      table.insert(pbt, pentry)
   end
   return pbt
end

function get_binding_table(bt_file)
   if not machine_friendly_binding_table then
      if not bt_file then
         error("bt_file must be specified or the BT pre-initialized")
      end
      local binding_table = read_binding_table(bt_file)
      machine_friendly_binding_table = pton_binding_table(binding_table)
   end
   return machine_friendly_binding_table
end
