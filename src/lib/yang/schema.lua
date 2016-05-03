-- Built in types (page 19)
--
--  +---------------------+-------------------------------------+
--  | Name                | Description                         |
--  +---------------------+-------------------------------------+
--  | binary              | Any binary data                     |
--  | bits                | A set of bits or flags              |
--  | boolean             | "true" or "false"                   |
--  | decimal64           | 64-bit signed decimal number        |
--  | empty               | A leaf that does not have any value |
--  | enumeration         | Enumerated strings                  |
--  | identityref         | A reference to an abstract identity |
--  | instance-identifier | References a data tree node         |
--  | int8                | 8-bit signed integer                |
--  | int16               | 16-bit signed integer               |
--  | int32               | 32-bit signed integer               |
--  | int64               | 64-bit signed integer               |
--  | leafref             | A reference to a leaf instance      |
--  | string              | Human-readable string               |
--  | uint8               | 8-bit unsigned integer              |
--  | uint16              | 16-bit unsigned integer             |
--  | uint32              | 32-bit unsigned integer             |
--  | uint64              | 64-bit unsigned integer             |
--  | union               | Choice of member types              |
--  +---------------------+-------------------------------------+
--
-- Module:
-- module <name of module> { ... }
--
-- required: namespace, prefix
-- optional: anyxml, augment, choice, contact, container, description, deviation,
--           extension, feature, grouping, identity, import, include, leaf, leaf-list
--           list, notification, organization, reference, revision, rpc, typedef, uses,
--           yang-version
--
module(..., package.seeall)

local validation = require("lib.yang.validation")

-- Use ffi types because they will validate that numeric values are being
-- provided. The downside is that integer overflow could occur on these. This
-- route has been selected as validation will be faster than attempting to
-- validate in Lua.
local ffi = require("ffi")
ffi.cdef[[
typedef struct { int8_t value; } int8box;
typedef struct { int16_t value; } int16box;
typedef struct { int32_t value; } int32box;
typedef struct { int64_t value; } int64box;
typedef struct { uint8_t value; } uint8box;
typedef struct { uint16_t value; } uint16box;
typedef struct { uint32_t value; } uint32box;
typedef struct { uint64_t value; } uint64box;
typedef struct { double value; } decimal64box;
]]


-- This is a boxed value for datatypes which are represeted in Lua and validated
-- in Lua. This includes everything except the numeric values.
local Box = {}
function Box.new(validate)
  local ret = {realroot={}}
  local mt = {
    __newindex = function (t, k, v)
      if validate then validate(v) end
        ret.realroot[k] = v
      end,
      __index = function(t, k)
        local v = ret.realroot[k]
        return v
      end,
  }
  return setmetatable(ret, mt)
end
-- Yang feature
local Feature = {}
function Feature.new(name)
  local ret = {config={name=name}}
  return setmetatable(ret, {__index = Feature})
end

function Feature:validate(statements)
  local cardinality = {description={0,1}, status={0,1}, refernece={0,1}}
  validation.cardinality("feature", name, cardinality, statements)
end

function Feature:consume(statements)
  if statements.description then
    self.config.description = statements.description[1].argument
  end
  if statements.reference then
    self.config.reference = statements.reference[1].argument
  end
  if statements.status then
    self.config.status = statements.reference[1].argument
  end
end

-- Yang Leaf
local Leaf = {}
function Leaf.new(name)
  local ret = {config={name=name}}
  ret.config.iffeature = {}
  return setmetatable(ret, {__index = Leaf})
end

function Leaf:validate(statements)
  local cardinality = {config={0,1}, default={0,1}, description={0,1},
                       mandatory={0,1}, reference={0,1}, status={0,1},
                       type={1,1}, units={0,1}, when={0,1}}
  validation.cardinality("leaf", name, cardinality, src)
end

function Leaf:consume(statements)
  if statements.default then self.config.default = statements.default end
  if statements.description then
    self.config.description = statements.description[1].argument
  end

  if statements["if-feature"] then
    for _, f in pairs(statements["if-feature"]) do
      table.insert(self.config.iffconfig["if-feature"], f.argument)
    end
  end

  -- Handle the type which will involve picking the correct box
  -- to store the value with validation if needed.
  self.config.type = statements.type[1].argument

  -- First deal with built in types.
  if self.config.type == "int8" then
    self.box = ffi.new("int8box")
  elseif self.config.type == "int16" then
    self.box = ffi.new("int16box")
  elseif self.config.type == "int32" then
    self.box = ffi.new("int32box")
  elseif self.config.type == "int64" then
    self.box = ffi.new("int64box")
  elseif self.config.type == "uint8" then
    self.box = ffi.new("uint8box")
  elseif self.config.type == "uint16" then
    self.box = ffi.new("uint16box")
  elseif self.config.type == "uint32" then
    self.box = ffi.new("uint32box")
  elseif self.config.type == "uint64" then
    self.box = ffi.new("uint64box")
  elseif self.config.type == "decimal64" then
    self.box = ffi.new("decimal64box")
  elseif self.config.type == "string" then
    self.box = Box.new()
  elseif self.config.type == "boolean" then
    self.box = Box.new(function (value)
      if type(value) ~= "boolean" then
        error(
          ("Value for '%s' must be true or false."):format(self.config.name))
      end
    end)
  else
    error(("Unknown type '%s' for leaf '%s'"):format(
      leaf_type, self.config.name))
  end
end

-- Yang list
local List = {}
function List.new(name)
  local ret = {config={name=name}}
  return setmetatable(ret, {__index = List})
end

function List:validate(statements)
  local cardinality = {config={0,1}, description={0,1}, key={0,1},
                       reference={0,1}, status={0,1}, when={0,1}}
  cardinality["max-elements"] = {0,1}
  cardinality["min-elements"] = {0,1}
  cardinality["ordered-by"] = {0,1}
  validation.cardinality("list", name, cardinality, statements)
end

function List:consume(statements)
  if statements.key then
    self.config.key = statements.key[1].argument
  end
  if statements.leaf then
    for _, leaf in pairs(statements.leaf) do
      self[leaf.argument] = Leaf.new(leaf.argument)
      self[leaf.argument]:consume(leaf.statements)
    end
  end
end

-- Yang group
local Grouping = {}
function Grouping.new(name)
  local ret = {config={name=name}}
  return setmetatable(ret, {__index = Grouping})
end

function Grouping:validate(statements)
  local cardinality = {description={0,1}, reference={0,1}, status={0,1}}
  validation.cardinality("grouping", name, cardinality, statements)
end

function Grouping:consume(statements)
  if statements.description then
    self.config.description = statements.description[1].argument
  end

  if statements.list then
    for _, list in pairs(statements.list) do
      self[list.argument] = List.new(list.argument)
      self[list.argument]:consume(list.statements)
    end
  end

  if statements.leaf then
    for _, leaf in pairs(statements.leaf) do
      self[leaf.argument] = Leaf.new(leaf.argument)
      self[leaf.argument]:consume(leaf.statements)
    end
  end
end

-- Yang Revision
local Revision = {}
function Revision.new(date)
  local ret = {config={date=date}}
  return setmetatable(ret, {__index = Revision})
end

function Revision:validate(statements)
  local cardinality = {description={0,1}, reference={0,1}}
  validation.cardinality("revision", self.config.date, cardinality, statements)
end

function Revision:consume(statements)
  self:validate(statements)

  if statements.description then
    self.config.description = statements.description[1].argument
  end
  if statements.description then
    self.config.reference = statements.reference.argument
  end
end

-- Yang Module
local Module = {}
function Module.new(name)
  local ret = {body={}, config={name=name}, modules={}, revisions={},
               features={}, groupings={}}
  return setmetatable(ret, {__index = Module})
end

function Module:load()
  -- Find the file and load it.
  print("DEBUG: loading module", self.config.name)
end

function Module:consume(statements)
  -- Validate the statements first.
  self:validate(statements)

  -- Set the meta information about the module
  self.config.namespace = statements.namespace[1].argument
  self.config.prefix = statements.prefix[1].argument

  if statements.organization then
    self.config.organization = statements.organization[1].argument
  end
  if statements.contact then
    self.config.contact = statements.contact[1].argument
  end

  if statements.description then
    self.config.description = statements.description[1].argument
  end
  
  -- Now handle the imports, as other things may reference them.
  if statements.import then
    for _, mod in pairs(statements.import) do
      self.modules[mod.argument] = Module.new(mod.argument)

      -- Ask the module to find and load itself.
      self.modules[mod.argument]:load()
    end
  end

  -- Handle revisions
  if statements.revision then
    for _, revision in pairs(statements.revision) do
      -- TODO: can or should we convert these revision date stamps.
      self.revisions[revision.argument] = Revision.new(revision.argument)
      self.revisions[revision.argument]:consume(revision.statements)
    end
  end

  -- Feature statements
  if statements.feature then
    for _, feature in pairs(statements.feature) do
      self.features[feature.argument] = Feature.new(feature.argument)
      self.features[feature.argument]:consume(feature.statements)
    end
  end

  -- Leaf statements
  if statements.leaf then
    for _, leaf in pairs(statements.revision) do
    end
  end

  -- List statements
  if statements.grouping then
    for _, grouping in pairs(statements.grouping) do
      self.groupings[grouping.argument] = Grouping.new(grouping.argument)
      self.groupings[grouping.argument]:consume(grouping.statements)
    end
  end
end

function Module:validate(statements)
  local cardinality = {contact={0,1}, description={0,1}, namespace={1,1},
                       organization={0,1}, prefix={1,1}, reference={0,1}}
  cardinality["yang-version"] = {0,1}
  validation.cardinality("module", self.name, cardinality, statements)
end


function extract_nodes(structure)
  local nodes = {}
  for _, v in pairs(structure) do
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

function load_schema(src)
  -- Okay conver the schema into something more useful.
  src = extract_nodes(src)

   -- Okay we're expecting a module at the top
  if not src.module then error("Expected 'module'") end
  local mod = Module.new(src.module[1].argument)
  mod:consume(src.module[1].statements)
  return mod
end


function selftest()
  local test_schema = [[module ietf-softwire {
  namespace "urn:ietf:params:xml:ns:yang:ietf-softwire";
  prefix "softwire";

  import ietf-inet-types {prefix inet; }
  import ietf-yang-types {prefix yang; }

  organization "Softwire Working Group";

  contact
    "
    Qi Sun sunqi.ietf@gmail.com
    Hao Wang wangh13@mails.tsinghua.edu.cn
    Yong Cui yong@csnet1.cs.tsinghua.edu.cn
    Ian Farrer ian.farrer@telekom.de
    Mohamed Boucadair mohamed.boucadair@orange.com
    Rajiv Asati rajiva@cisco.com
    ";

  description
    "This document defines a YANG data model for the configuration and
    management of IPv4-in-IPv6 Softwire Border Routers and Customer
    Premises Equipment. It covers Lightweight 4over6, MAP-E and MAP-T
    Softwire mechanisms.

    Copyright (c) 2014 IETF Trust and the persons identified
    as authors of the code. All rights reserved.
    This version of this YANG module is part of RFC XXX; see the RFC
    itself for full legal notices.";


  revision 2015-09-30 {
    description
      "Version-04: fix YANG syntax; Add flags to map-rule; Remove
                  the map-rule-type element. ";
       reference "tbc";
  }

  revision 2015-04-07 {
    description
      "Version-03: Integrate lw4over6; Updata state nodes; Correct
          grammar errors; Reuse groupings; Update descriptions.
          Simplify the model.";
       reference "tbc";
  }

  revision 2015-02-10 {
    description
      "Version-02: Add notifications.";
       reference "tbc";
  }


  revision 2015-02-06 {
    description
      "Version-01: Correct grammar errors; Reuse groupings; Update
      descriptions.";
       reference "tbc";
  }

  revision 2015-02-02 {
    description
      "Initial revision.";
       reference "tbc";
  }

  feature lw4over6 {
      description
        "Lightweight 4over6 moves the Network Address and Port
        Translation (NAPT) function from the centralized DS-Lite tunnel
        concentrator to the tunnel client located in the Customer
        Premises Equipment (CPE).  This removes the requirement for a
        Carrier Grade NAT function in the tunnel concentrator and
        reduces the amount of centralized state that must be held to a
        per-subscriber level.  In order to delegate the NAPT function
        and make IPv4 Address sharing possible, port-restricted IPv4
        addresses are allocated to the CPEs.";
      reference
        "I-D.ietf-softwire-lw4over6";
    }

    feature map-e {
      description
        "MAP-E is a mechanism for transporting IPv4 packets across an
        IPv6 network using IP encapsulation, and a generic mechanism
        for mapping between IPv6 addresses and IPv4 addresses and
        transport layer ports.";
      reference
        "I-D.ietf-softwire-map";
    }

    grouping map-rule-table {
      description
        "The (conceptual) table containing rule Information for
        a specific mapping rule. It can also be used for row creation.";
      list map-rule-entry {
        key "id";
        leaf id {
          type uint8;
        }

        leaf testbool {
          type boolean;
        }
      }
    }
   }]]

  -- Convert the schema using the already tested parser.
  local parser = require("lib.yang.parser")
  local schema = parser.parse_string(test_schema, "schema selftest")
  local mod = load_schema(schema)

  assert(mod.config.name == "ietf-softwire")
  assert(mod.config.namespace == "urn:ietf:params:xml:ns:yang:ietf-softwire")
  assert(mod.config.prefix == "softwire")
  assert(mod.config.contact)
  assert(mod.config.organization)
  assert(mod.config.description)

  -- Check both modules exist. (Also need to check they've loaded)
  assert(mod.modules["ietf-inet-types"])
  assert(mod.modules["ietf-yang-types"])

  -- Check all revisions are accounted for.
  assert(mod.revisions["2015-02-02"].config.description)
  assert(mod.revisions["2015-02-06"].config.description)
  assert(mod.revisions["2015-02-10"].config.description)
  assert(mod.revisions["2015-04-07"].config.description)
  assert(mod.revisions["2015-09-30"].config.description)

  -- Check that the feature statements are there.
  assert(mod.features["lw4over6"].config.description)
  assert(mod.features["lw4over6"].config.reference)
  assert(mod.features["map-e"].config.description)
  assert(mod.features["map-e"].config.reference)

  -- Check the grouping exists and has everything we'd want it to.
  assert(mod.groupings["map-rule-table"].config.description)
  assert(mod.groupings["map-rule-table"]["map-rule-entry"])

  -- Check that the list was in the group was identified correctly.
  local list = mod.groupings["map-rule-table"]["map-rule-entry"]
  assert(list.config.key == "id")
  assert(list.id.config.type == "uint8")

  -- Test both setting and getting ints and bools
  list.id.box.value = 72
  assert(list.id.box.value == 72)
  list.testbool.box.value = true
  assert(list.testbool.box.value == true)
  list.testbool.box.value = false
  assert(list.testbool.box.value == false)

  -- Should fail.
  list.testbool.box.value = "hello"
end
