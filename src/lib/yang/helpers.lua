-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local h = require("syscall.helpers")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local corelib = require("core.lib")

function extract_nodes(schema)
   local nodes = {}
   for _, v in pairs(schema) do
      -- Recursively apply this
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
function IPv4Box.new()
   local ret = {root={}}
   return setmetatable(ret, {
      __index = function (t, k) return rawget(ret, "root").value end,
      __newindex = function(t, k, v)
         local ipv4boxed, err = ipv4:pton(v)
         if ipv4boxed == false then error(err) end
         rawget(ret, "root").value = ipv4boxed
      end
   })
end

IPv6Box = {}
function IPv6Box.new()
   local ret = {root={}}
   return setmetatable(ret, {
      __index = function (t, k) return rawget(ret, "root").value end,
      __newindex = function(t, k, v)
         local ipv6boxed, err = ipv6:pton(v)
         if ipv6boxed == false then error(err) end
         rawget(ret, "root").value = ipv6boxed
      end
   })
end

IPv4PrefixBox = {}
function IPv4PrefixBox.new()
   local ret = {root={}}
   return setmetatable(ret, {
      __newindex = function (t, k, v)
         -- split the netmask and prefix up.
         local raw = h.split("/", v)
         local addr, err = ipv4:pton(raw[1])
         if addr == false then error(err) end
         local prefix = tonumber(raw[2])
         if prefix > 32 or prefix < 0 then
            error(("The prefix length is invalid. (%s)"):format(raw[2]))
         end
         rawget(ret, "root").value = {addr, prefix}
      end,
      __index = function (t, k, v) return rawget(ret, "root").value end
   })
end

IPv6PrefixBox = {}
function IPv6PrefixBox.new()
   local ret = {root={}}
   return setmetatable(ret, {
      __newindex = function (t, k, v)
         -- split the netmask and prefix up.
         local raw = h.split("/", v)
         local addr, err = ipv6:pton(raw[1])
         if addr == false then error(err) end
         local prefix = tonumber(raw[2])
         if prefix > 128 or prefix < 0 then
            error(("The prefix length is invalid. (%s)"):format(raw[2]))
         end
         rawget(ret, "root").value = {addr, prefix}
      end,
      __index = function (t, k, v) return rawget(ret, "root").value end
   })
end

Enum = {}
function Enum.new(options)
   local ret = {root={}}
   local opts = {}
   for _, option in pairs(options) do
      opts[option] = option
   end
   return setmetatable(ret, {
      __index = function (t, k) return rawget(ret, "root").value end,
      __newindex = function(t, k, v)
         if opts[v] then rawget(ret, "root").value = v
         else error("Value "..v.." is not a valid option for this Enum.") end
      end
   })
end

Union = {}
function Union.new(types)
   local ret = {root={}, types={}}

   -- Importing here to prevent cyclic imports.
   local Leaf = require("lib.yang.schema").Leaf
   for _, name in pairs(types) do
      -- 9.12 specifies unions cannot contain "leafref" or "empty"
      if name == "empty" or name == "leafref" then
         error("Union type cannot contain 'empty' or 'leafref'")
      end
      ret.types[name] = Leaf:provide_box(name)
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
            -- This could be because it's a method defined on Container.
            return Container[k]
         elseif prop.value == nil then
            return prop
         else
            return prop.value
         end
      end,
   })
end

function Container:set_template(template)
   rawset(self, "template", template)
end
function Container:get_template(template)
   return rawget(self, "template")
end

function Container:add_item(item)
   local root = rawget(self, "root")
   local base = rawget(self, "base")
   local path = rawget(self, "path")
   
   -- Verify that the item is being added to a list type.
   local schema = base:get_schema(path)
   if schema:get_type() ~= "list" then
      error("Can't add item to '"..schema:get_type().."'")
   end

   -- Each entry will have their own container which is a copy of the template.
   local template = assert(self:get_template(), "Must set template to add item")
   local con = template:duplicate()

   -- Find the leaves from the schema, if it's a group then find the parent.
   local leaves
   if schema.uses then
      leaves = base:schema_for_uses(schema).leaves
   else
      leaves = schema.leaves
   end

   -- Create a new table of item + leavesf
   local data = corelib.deepcopy(item)
   for name, leaf in pairs(leaves) do data[name] = leaf end

   -- Add the data to the container.
   for name, leaf in pairs(data) do
      if leaves[name] == nil then
         error("Unknown field in list: '"..name.."'")
      elseif item[name] == nil and leaves[name].mandatory then
         error("Field "..name.." not provided but is mandatory.")
      elseif item[name] then
         con[name] = item[name]
      end
   end

   -- Add the container entry to container.
   table.insert(root, con)
end

function Container:add_container(name)
   self:add_to_root(name, Container.new(self, name))
end

function Container:add_to_root(key, value)
   local root = rawget(self, "root")
   root[key] = value
end

function Container:duplicate()
   -- Produces and returns a duplicate of the container
   local root = corelib.deepcopy(rawget(self, "root"))
   local copy = Container.new(rawget(self, "base"), rawget(self, "path"))
   rawset(copy, "root", root)
   return copy
end

-- Functions to help testing.
function asserterror(func, ...)
   local success, val = pcall(func, ...)
   if success then
      error(("Asserterror failed! Returned with '%s'"):format(val))
   end
end

function cardinality(kw, path, statements, haystack)
   for s, c in pairs(statements) do
      if (c[1] >= 1 and (not haystack[s])) or
         (#statements[s] < c[1] and #statements[s] > c[2]) then
         if c[1] == c[2] then
            error(("Expected %d %s statement(s) in %s:%s"):format(
               c[1], s, kw, path))
         else
            local err = "Expected between %d and %d of %s statement(s) in %s:%s"
            error((err):format(c[1], c[2], s, kw, path))
         end
      end
   end
   return true
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

   -- Test the union box (both uint8, ipv4 - valid and invalid data)
   root.testbox = Union.new({"uint8", "inet:ipv4-address"})
   con.testbox = 72
   assert(con.testbox == 72)
   con.testbox = "8.8.8.8"
   assert(ipv4:ntop(con.testbox) == "8.8.8.8")
   asserterror(setvalue, con, "testbox", "should fail")

   -- Test the IPv4 box (both valid and invalid data).
   root.testbox = IPv4Box.new()
   con.testbox = "8.8.8.8"
   assert(ipv4:ntop(con.testbox) == "8.8.8.8")
   asserterror(setvalue, con, "testbox", "256.8.8.8")

   -- Test the IPv6 box (both valid and invalid data).
   root.testbox = IPv6Box.new()
   con.testbox = "::1"
   assert(ipv6:ntop(con.testbox) == "::1")
   asserterror(setvalue, con, "testbox", "not ipv6")

   -- Testing enums (both valid and invalid values)
   root.testbox = Enum.new({"Banana", "Apple"})
   con.testbox = "Banana"
   assert(con.testbox == "Banana")
   con.testbox = "Apple"
   assert(con.testbox == "Apple")
   asserterror(setvalue, con, "testbox", "Pear")

   -- Testing ipv4 prefix
   root.testbox = IPv4PrefixBox.new()
   con.testbox = "192.168.0.0/24"
   local rtn = assert(con.testbox)
   assert(ipv4:ntop(rtn[1]) == "192.168.0.0")
   assert(rtn[2] == 24)
   asserterror(setvalue, con, "testbox", "Incorrect value")
   asserterror(setvalue, con, "testbox", "192.168.0.0/33")
   asserterror(setvalue, con, "testbox", "192.168.0.0/-1")
   asserterror(setvalue, con, "testbox", "192.256.0.0/24")

   -- Testing ipv6 prefix
   root.testbox = IPv6PrefixBox.new()
   con.testbox = "2001:db8::/32"
   local rtn = assert(con.testbox)
   assert(ipv6:ntop(rtn[1]) == "2001:db8::")
   assert(rtn[2] == 32)
   asserterror(setvalue, con, "testbox", "Incorrect value")
   asserterror(setvalue, con, "testbox", "2001:db8::/129")
   asserterror(setvalue, con, "testbox", "2001:db8::/-1")
   asserterror(setvalue, con, "testbox", "FFFFF:db8::/32")
end
