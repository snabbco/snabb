-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local h = require("syscall.helpers")
local ffi = require("ffi")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local corelib = require("core.lib")

-- Create small getter and setter wrapper for ffi structs.
local FFIType = {}

function FFIType:set(value)
   self.value = value
end

function FFIType:get()
   return self.value
end


-- This wraps the FFIType to provide it with the box name, 

-- Use ffi types because they will validate that numeric values are being
-- provided. The downside is that integer overflow could occur on these. This
-- route has been selected as validation will be faster than attempting to
-- validate in Lua.
local box_types = {
   int8 = ffi.typeof("struct { int8_t value; }"),
   int16 = ffi.typeof("struct { int16_t value; }"),
   int32 = ffi.typeof("struct { int32_t value; }"),
   int64 = ffi.typeof("struct { int64_t value; }"),
   uint8 = ffi.typeof("struct { uint8_t value; }"),
   uint16 = ffi.typeof("struct { uint16_t value; }"),
   uint32 = ffi.typeof("struct { uint32_t value; }"),
   uint64 = ffi.typeof("struct { uint64_t value; }"),
   decimal64 = ffi.typeof("struct { double value; }"),
   boolean = ffi.typeof("struct { bool value; }"),
}

-- Iterate through the boxes and set the FFIType metatype
for _, box in pairs(box_types) do
   ffi.metatype(box, {__index=FFIType})
end

-- Add inet types, found: https://tools.ietf.org/html/rfc6021
-- Should be done via yang module import but using ad-hoc method for now.
box_types["yang:zero-based-counter64"] = function ()
   return box_types.uint64(0)
end

function create_box(leaf_type, default)
   local box = assert(box_types[leaf_type], "Unsupported type: "..leaf_type)
   if box and default ~= nil then
      box = box(default)
   elseif box then
      box = box()
   end
   return box
end

function extract_nodes(schema)
   -- This function takes a table which is in the format:
   -- {1={keyword="leaf", statements={...}}}
   -- and converts this to a more useful easy to access:
   -- {leaf={1={...}}}

   local nodes = {}
   for _, v in pairs(schema) do
      -- Node has statements (children) so we should recursively apply the
      -- `extract_nodes` function to them so the entire tree is extracted
      if v.statements then v.statements = extract_nodes(v.statements) end
      if nodes[v.keyword] then
         table.insert(nodes[v.keyword], v)
      else
         nodes[v.keyword] = {v}
      end
   end
   return nodes
end

local StringBox = {}
function StringBox.new()
   return setmetatable({}, {__index=StringBox})
end

function StringBox:get()
   return self.value
end

function StringBox:set(value)
   self.value = value
end
box_types["string"] = StringBox.new

local IPv4Box = {}
function IPv4Box.new(address)
   local ret = {root={}}
   if address then ret.box = ipv4:pton(address) end
   return setmetatable(ret, {__index=IPv4Box})
end
function IPv4Box:get()
   return self.box
end
function IPv4Box:set(address)
   self.box = assert(ipv4:pton(address))
end
box_types["inet:ipv4-address"] = IPv4Box.new

local IPv6Box = {}
function IPv6Box.new(address)
   local ret = {}
   if address then ret.box = ipv6:pton(address) end
   return setmetatable(ret, {__index=IPv6Box})
end
function IPv6Box:get()
   return self.box
end
function IPv6Box:set(address)
   self.box = assert(ipv6:pton(address))
end
box_types["inet:ipv6-address"] = IPv6Box.new

local IPv4PrefixBox = {}
function IPv4PrefixBox.new()
   local ret = {root={}}
   return setmetatable(ret, {__index=IPv4PrefixBox})
end

function IPv4PrefixBox:get()
   return self.value
end
box_types["inet:ipv4-prefix"] = IPv4PrefixBox.new

function IPv4PrefixBox:set(value)
   -- split the netmask and prefix up.
   local raw = h.split("/", value)
   local addr, err = ipv4:pton(raw[1])
   if addr == false then error(err) end
   local prefix = tonumber(raw[2])
   if prefix > 32 or prefix < 0 then
      error(("The prefix length is invalid. (%s)"):format(raw[2]))
   end
   self.value = {addr, prefix}
end

local IPv6PrefixBox = {}
function IPv6PrefixBox.new()
   local ret = {root={}}
   return setmetatable(ret, {__index=IPv6PrefixBox})
end
function IPv6PrefixBox:get()
   return self.value
end
function IPv6PrefixBox:set(value)
   -- split the netmask and prefix up.
   local raw = h.split("/", value)
   local addr, err = ipv6:pton(raw[1])
   if addr == false then error(err) end
   local prefix = tonumber(raw[2])
   if prefix > 128 or prefix < 0 then
      error(("The prefix length is invalid. (%s)"):format(raw[2]))
   end
   self.value = {addr, prefix}
end
box_types["inet:ipv6-prefix"] = IPv6PrefixBox.new

local Enum = {}
function Enum.new(options)
   local opts = {}
   for _, option in pairs(options) do
      opts[option] = option
   end
   return setmetatable({options=opts}, {__index=Enum})
end

function Enum:get()
   return self.value
end

function Enum:set(value)
   if self.options[value] then
      self.value = value
   else
      error("Value "..value.." is not a valid option for this Enum.")
   end
end
box_types["enumeration"] = Enum.new

local Union = {}
function Union.new(types)
   local ret = {types={}}
   for _, name in pairs(types) do
      -- 9.12 specifies unions cannot contain "leafref" or "empty"
      if name == "empty" or name == "leafref" then
         error("Union type cannot contain 'empty' or 'leafref'")
      end
      ret.types[name] = create_box(name)
   end
   return setmetatable(ret, {__index=Union})
end

function Union:get()
   if self.box then
      return self.box:get()
   end
end

function Union:set(v)
   local function setbox(b, v) b:set(v) end
   for _, box in pairs(self.types) do
      local valid = pcall(setbox, box, v)
      if valid then
         self.box = box
         return -- don't want to continue.
      end
   end
   error(("Unable to find matching type for '%s' (%s)"):format(v, type(v)))
end

box_types["union"] = Union.new

Container = {}
function Container.new(base, path)
   local ret = {root={}, base=base, path=path}
   return setmetatable(ret, {
      __newindex = function (_, k, v)
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
         box:set(v)
      end,
      __index = function(t, k)
         local root = rawget(t, "root")
         local prop = root[k]

         if not prop then
            -- This could be because it's a method defined on Container.
            return Container[k]
         elseif prop.get == nil then
            return prop
         else
            return prop:get()
         end
      end,
   })
end

function Container:set_template(template)
   rawset(self, "template", template)
end
function Container:get_template()
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
   for name, _ in pairs(data) do
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
   root.testbox = box_types["inet:ipv4-address"]()
   con.testbox = "8.8.8.8"
   assert(ipv4:ntop(con.testbox) == "8.8.8.8")
   asserterror(setvalue, con, "testbox", "256.8.8.8")

   -- Test the IPv6 box (both valid and invalid data).
   root.testbox = box_types["inet:ipv6-address"]()
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
