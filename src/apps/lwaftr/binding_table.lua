module(..., package.seeall)

local ffi = require("ffi")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")

local binding_table = {
 {'127:2:3:4:5:6:7:128', '178.79.150.233', 1, 100, '8:9:a:b:c:d:e:f'},
 {'127:11:12:13:14:15:16:128', '178.79.150.233', 101, 64000},
 {'127:22:33:44:55:66:77:128', '178.79.150.15', 5, 7000}
}

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

function get_binding_table()
   if not machine_friendly_binding_table then
      machine_friendly_binding_table = pton_binding_table(binding_table)
   end
   return machine_friendly_binding_table
end
