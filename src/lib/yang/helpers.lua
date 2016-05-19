-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")

function extract_nodes(schema)
   local nodes = {}
   for _, v in pairs(schema) do
      -- Recursively apply this.
      if v.statements then v.statements = extract_nodes(v.statements) end

      -- Add to the nodes table.  
      if nodes[v.keyword] then
         table.insert(nodes[v.keyword], v)
      else
         nodes[v.keyword] = {v}
      end
   end
   return nodes
end

IPv4Box = {}
function IPv4Box.new(address)
   local ret = {root={}}
   if address then ret.value = ipv4:pton(address) end
   return setmetatable(ret, {
      __index = function (t, k) return rawget(ret, "root").value end,
      __newindex = function(t, k, v)
         rawget(ret, "root").value = ipv4:pton(v)
      end
   })
end

IPv6Box = {}
function IPv6Box.new(address)
   local ret = {root={}}
   if address then ret.value = ipv6:pton(address) end
   return setmetatable(ret, {
      __index = function (t, k) return rawget(ret, "root").value end,
      __newindex = function(t, k, v)
         rawget(ret, "root").value = ipv6:pton(v)
      end
   })
end

Enum = {}
function Enum.new(options)
   local ret = {root={}}
   for i, option in pairs(options) do
      ret[i] = option
   end
   return setmetatable(ret, {
      __index = function (t, k) return rawget(ret, "root")[k].value end,
      __newindex = function(t, k, v)
         if rawget(ret, v) then rawget(ret, "root")[k].value = v end
      end
   })
end

Union = {}
function Union.new(types)
   local ret = {root={}, types={}}

   -- Importing here to prevent cyclic imports.
   local Leaf = require("lib.yang.schema").Leaf
   for _, name in pairs(types) do
      ret.types[name] = Leaf.provide_box(nil, name)
   end

   return setmetatable(ret, {
      __index = function (t, k)
         return rawget(ret, "root").box.value
      end,
      __newindex = function(t, k, v)
         local function setbox(dest, v) dest.value = v end
         local root = rawget(ret, "root")
         for name, box in pairs(rawget(ret, "types")) do
            local valid = pcall(setbox, box, v)
            if valid then
               root.box = box
               return -- don't want to continue.
            end
         end
         error(("Unable to find matching type for '%s' (%s)"):format(v, type(v)))
      end
   })
end

Container = {}
function Container.new(base, path)
   local ret = {root={}, base=base, path=path}
   return setmetatable(ret, {
      __newindex = function (t, k, v)
         -- Validate the value prior to setting it.
         local node_path = ret.path.."."..k
         local schema = assert(
            ret.base:get_schema(ret.path.."."..k),
            ("No schema found at: %s.%s"):format(ret.path, k)
         )

         if schema.validation then
            for _, validation in pairs(schema.validation) do
               validation(v)
            end
         end

         local box = assert(ret.root[k], "Unknown leaf '"..node_path.."'")
         box.value = v
      end,
      __index = function(t, k)
         local table = rawget(t, "root")
         local prop = table[k]
         if not prop then
            return prop
         elseif prop.value == nil then
            return prop
         else
            return prop.value
         end
      end
   })
end

function pp(x, n)
   if n ~= nil and n <= 0 then return nil end
   if type(x) == "table" then
      io.write("{")
      local first = true
      for k,v in pairs(x) do
         if not first then
            io.write(", ")
         end
         io.write(k.."=")
         if n then pp(v, n-1) else pp(v) end
         first = false
      end
      io.write("}")
   elseif type(x) == "string" then
      io.write(x)
   else
      io.write(("<Unsupported type '%s'>"):format(type(x)))
   end
end

-- Functions to help testing.
function asserterror(func, ...)
   local success, val = pcall(func, ...)
   if success then
      error(("Asserterror failed! Returned with '%s'"):format(val))
   end
end

function setvalue(t, k, v)
   t[k] = v
end

function selftest()
   local base = require("lib.yang.yang").Base.new()
   -- Register a fake schema to satisfy the requirements.
   base:add_cache("mod.testbox", {})

   local con = Container.new(base, "mod")
   local root = rawget(con, "root")

   -- Test the union box
   root.testbox = Union.new({"uint8", "inet:ipv4-address"})
   
   -- Allow a uint8 value.
   con.testbox = 72
   assert(con.testbox == 72)
   
   -- Allow a valid IPv4 address
   con.testbox = "8.8.8.8"
   assert(ipv4:ntop(con.testbox) == "8.8.8.8")
   
   -- setting "should fail" is not uint8 or valid IPv4 address so should fail.
   asserterror(setvalue, con, "testbox", "should fail")


   -- Test the IPv4 box.
   root.testbox = IPv4Box.new()

   -- Set it to a valid IPv4 address
   con.testbox = "8.8.8.8"
   assert(ipv4:ntop(con.testbox) == "8.8.8.8")

   -- Set it to something erroneous and check it fails
   con.testbox = "256.8.8.8"
   assert(ipv4:ntop(con.testbox) == "256.8.8.8")
end