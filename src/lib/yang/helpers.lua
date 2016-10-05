-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local h = require("syscall.helpers")
local ffi = require("ffi")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local corelib = require("core.lib")
local ethernet = require("lib.protocol.ethernet")

-- Create small getter and setter wrapper for ffi structs.
local FFIType = {}

function FFIType:set(value)
   self.value = convert(value)
end

function FFIType:get()
   return self.value
end


-- Converts a type to a native lua type, this will only work for things we've coded
-- to convert (i.e. it's not general purpose).
function convert(value)
   -- First try boolean.
   if value == "true" then
      return true
   elseif value == "false" then
      return false
   else
      return tonumber(value) -- returns nil if no number is found
   end
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
   boolean = ffi.typeof("struct { bool value; }")
}

-- Iterate through the boxes and set the FFIType metatype
for n, box in pairs(box_types) do
   ffi.metatype(box, {__index=FFIType,})
end

-- Add inet types, found: https://tools.ietf.org/html/rfc6021
-- Should be done via yang module import but using ad-hoc method for now.
box_types["yang:zero-based-counter64"] = function()
   return box_types.uint64(0)
end

-- Add the types defined in the snabb-softwire yang module. This should be
-- handled by consumption of the 'typedef' statements in the future, however
-- for now, hard code them in.
box_types["PacketPolicy"] = function()
   local enum_opts = {"allow", "deny"}
   return box_types.enumeration(enum_opts)
end

-- WARNING: This doesn't check the range as defined in the config
box_types["PositiveNumber"] = function(...)
   return box_types.uint32()
end

-- WARNING: This doesn't check the range as defined in the config
box_types["VlanTag"] = function(...)
   return box_types.uint16()
end

function create_box(leaf_type, arguments)
   local box = assert(box_types[leaf_type], "Unsupported type: "..leaf_type)
   if box and arguments ~= nil then
      box = box(arguments)
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
      elseif v.keyword then
         nodes[v.keyword] = {v}
      end
   end
   return nodes
end

local StringBox = {}
function StringBox.new(options, default)
   local strbox = setmetatable({}, {__index=StringBox})
   if default ~= nil then
      strbox:set(default)
   end
   return strbox
end

function StringBox:get()
   return self.value
end

function StringBox:set(value)
   self.value = value
end
function StringBox.get_type() return "box-string" end
box_types["string"] = StringBox.new

local MacAddress = {}
function MacAddress.new(options, default)
   local mac =  setmetatable({}, {__index=MacAddress})
   if default ~= nil then
      mac:set(default)
   end
   return mac
end
function MacAddress:get()
   return self.box
end
function MacAddress:set(address)
   self.box = assert(ethernet:pton(address))
end
function MacAddress.get_type() return "box-inet:mac-address" end
box_types["inet:mac-address"] = MacAddress.new

local IPv4Box = {}
function IPv4Box.new(options, default)
   local ipv4 = setmetatable({}, {__index=IPv4Box})
   if default ~= nil then
      ipv4:set(default)
   end
   return ipv4
end
function IPv4Box:get()
   return self.box
end
function IPv4Box:set(address)
   self.box = assert(ipv4:pton(address))
end
function IPv4Box.get_type() return "box-inet:ipv4-address" end
box_types["inet:ipv4-address"] = IPv4Box.new

local IPv6Box = {}
function IPv6Box.new(options, default)
   local ipv6 = setmetatable({}, {__index=IPv6Box})
   if default ~= nil then
      ipv6:set(default)
   end
   return ipv6
end
function IPv6Box:get()
   return self.box
end
function IPv6Box:set(address)
   self.box = assert(ipv6:pton(address))
end
function IPv6Box.get_type() return "box-inet:ipv6-address" end
box_types["inet:ipv6-address"] = IPv6Box.new

local IPv4PrefixBox = {}
function IPv4PrefixBox.new(options, default)
   local ret = {root={}}
   local ipv4_prefix =  setmetatable(ret, {__index=IPv4PrefixBox})
   if default ~= nil then
      ipv4_prefix:set(default)
   end
   return ipv4_prefix
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
function IPv4PrefixBox.get_type() return "box-inet:ipv4-prefix" end

local IPv6PrefixBox = {}
function IPv6PrefixBox.new(options, default)
   local ret = {root={}}
   local ipv6_prefix = setmetatable(ret, {__index=IPv6PrefixBox})
   if default ~= nil then
      ipv6_prefix:set(default)
   end
   return ipv6_prefix
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
function IPv6PrefixBox.get_type() return "box-inet:ipv6-prefix" end
box_types["inet:ipv6-prefix"] = IPv6PrefixBox.new

local Enum = {}
function Enum.new(options, default)
   local opts = {}
   for _, option in pairs(options) do
      opts[option] = option
   end
   local mt = {__index=Enum, options=options, default=default}
   local initialized_enum = setmetatable({options=opts}, mt)
   if default ~= nil then
      initialized_enum:set(default)
   end
   return initialized_enum
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
function Enum.get_type() return "box-enumeration" end
box_types["enumeration"] = Enum.new

local Union = {}
function Union.new(types, default)
   local ret = {types={}}
   for _, name in pairs(types) do
      -- 9.12 specifies unions cannot contain "leafref" or "empty"
      if name == "empty" or name == "leafref" then
         error("Union type cannot contain 'empty' or 'leafref'")
      end
      ret.types[name] = create_box(name, nil, default)
   end
   return setmetatable(ret, {__index=Union, options=types, default=default})
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
function Union.get_type() return "box-union" end

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
            return rawget(Container, k)
         elseif prop.get == nil then
            return prop
         else
            return prop:get()
         end
      end,
   })
end

function Container.get_type() return "container" end

function Container:set_template(template)
   rawset(self, "template", template)
end
function Container:get_template()
   return rawget(self, "template")
end

local function pp(x)
   if type(x) == "table" then
      io.write("{")
      local first = true
      for k,v in pairs(x) do
         if not first then
            io.write(", ")
         end
         io.write(k.."=")
         pp(v)
         first = false
      end
      io.write("}")
   elseif type(x) == "string" then
      io.write(x)
   else
      error("Unsupported type")
   end
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
   for name, leaf in pairs(leaves) do
      data[name] = leaf
   end

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

   -- Create the key
   local key = item[schema.key]

   if key == nil then
      error("List item's key ("..schema.key..") cannot be null")
   end

   -- Add the container entry to container.
   root[key] = con
end

function Container:add_container(name, container)
   if container == nil then
      container = Container.new(self, name)
   end
   self:add_to_root(name, container)
end

function Container:add_to_root(key, value)
   local root = rawget(self, "root")
   root[key] = value
end

function Container:duplicate()
   local root = rawget(self, "root")
   local dup = {}

   for k, v in pairs(root) do
      -- If "v" is a table with the method .get_type it retrives the type
      local table_type
      if type(v) == "table" and v.get_type ~= nil then table_type = v.get_type() end
      if table_type == "container" then
         dup[k] = v:duplicate()
      elseif table_type and table_type:sub(1, 4) == "box-" then
         local box_type = table_type:sub(5, table_type:len())
         local options = getmetatable(v).options
         local defaults = getmetatable(v).defaults
         local dup_box = create_box(box_type, options, defaults)
         dup[k] = dup_box
      elseif type(v) == "cdata" then
         local dup_ctype = ffi.new(ffi.typeof(v))
         ffi.copy(dup_ctype, v, ffi.sizeof(v))
         dup[k] = dup_ctype
      end
   end

   local duplicate_container = Container.new(
      rawget(self, "base"),
      rawget(self, "path")
   )
   rawset(duplicate_container, "root", dup)
   return duplicate_container
end

function Container:get_type() return "container" end

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

   -- Remove following when typedef is supported.
   -- Test the PacketPolicy enum
   root.testbox = create_box("PacketPolicy")
   con.testbox = "allow"
   assert(con.testbox == "allow")
   con.testbox = "deny"
   assert(con.testbox == "deny")
   asserterror(setvalue, con, "testbox", "not allow or deny")
   asserterror(setvalue, con, "testbox", "alow")
end
