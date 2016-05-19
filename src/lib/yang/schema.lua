-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
-- This module implements the schema tree and validation for YANG. It represents
-- the YANG statements with lua tables and provides a fast but flexible way to
-- represent and validate statements.
-- 
-- Since YANG statements are encapsulated in modules at the highest level one
-- should take their pre-parsed YANG document containing the module and load it
-- into the Module table.
--
-- This relies on the "Base" table which can be found in the yang.lua file.
module(..., package.seeall)

local validation = require("lib.yang.validation")
local helpers = require("lib.yang.helpers")
local h = require("syscall.helpers")

-- Use ffi types because they will validate that numeric values are being
-- provided. The downside is that integer overflow could occur on these. This
-- route has been selected as validation will be faster than attempting to
-- validate in Lua.
local ffi = require("ffi")
local int8box = ffi.typeof("struct { int8_t value; }")
local int16box = ffi.typeof("struct { int16_t value; }")
local int32box = ffi.typeof("struct { int32_t value; }")
local int64box = ffi.typeof("struct { int64_t value; }")
local uint8box = ffi.typeof("struct { uint8_t value; }")
local uint16box = ffi.typeof("struct { uint16_t value; }")
local uint32box = ffi.typeof("struct { uint32_t value; }")
local uint64box = ffi.typeof("struct { uint64_t value; }")
local decimal64box = ffi.typeof("struct { double value; }")

Leaf = {}
function Leaf.new(base, path, src)
   local self = setmetatable({}, {__index=Leaf, path=path})

   -- Parse the schema to find the metadata
   self:validate_schema(src)
   base:add_cache(path, self)

   self.type = src.type[1].argument
   if src.type[1].statements then
      local typeinfo = src.type[1].statements
      if typeinfo.range then
         local range = h.split("%.%.", typeinfo.range[1].argument)
         self.range = {tonumber(range[1]), tonumber(range[2])}
      elseif typeinfo.enum then
         self.enums = {}
         for _, v in pairs(typeinfo.enum) do
            self.enums[v.argument] = v.argument
         end
      end
   end
   if src.description then
      self.description = src.description[1].argument
   end

   if src.default then
      self.default = src.default[1].argument
   end

   if src["if-feature"] then
      self["if-feature"] = {}
      for _, f in pairs(src["if-feature"]) do
         table.insert(self["if-feature"], f.argument)
      end
   end

   if src.mandatory then
      self.mandatory = src.mandatory[1].argument == "true"
   end

   -- Add validators if we need to.
   if self.mandatory then
      if not self.validation then self.validation = {} end
      table.insert(self.validation, function (v)
         if not v then
            self:error("Value is mandatory")
         end
      end)
   end
   if self.range then
      if not self.validation then self.validation = {} end
      self.validation[#self.validation + 1] = function(v)
         if v < self.range[1] or v > self.range[2] then
            self:error("Value '%s' is out of range", path, value)
         end
      end
   end
   if self.enums then
      if not self.validation then self.validation = {} end
      self.validation[#self.validation + 1] = function (v)
         if v and not self.enums[v] then
            self:error("Value '%s' is not one of the Enum values", v)
         end
      end
   end
   return self
end

function Leaf:error(msg, ...)
   local path = getmetatable(self).path
   error(("%s: %s"):format(path, msg:format(...)))
end

function Leaf:validate_schema(schema)
   local cardinality = {config={0,1}, default={0,1}, description={0,1},
                        mandatory={0,1}, reference={0,1}, status={0,1},
                        type={1,1}, units={0,1}, when={0,1}}
   validation.cardinality("leaf", getmetatable(self).path, cardinality, schema)
end

function Leaf:provide_box(leaf_type, statements)
   local box

   if not leaf_type then leaf_type = self.type end

   if leaf_type == "int8" then
      box = int8box()
   elseif leaf_type == "int16" then
      box = int16box()
   elseif leaf_type == "int32" then
      box = int32box()
   elseif leaf_type == "int64" then
      box = int64box()
   elseif leaf_type == "uint8" then
      box = uint8box()
   elseif leaf_type == "uint16" then
      box = uint16box()
   elseif leaf_type == "uint32" then
      box = uint32box()
   elseif leaf_type == "uint64" then
      box = uint64box()
   elseif leaf_type == "decimal64" then
      box = decimal64box()
   elseif leaf_type == "string" then
      box = {}
   elseif leaf_type == "boolean" then
      box = {}
   elseif leaf_type == "enumeration" then
      box = helpers.Enum.new(self.enums)
   elseif leaf_type == "union" then
      box = helpers.Union.new(statements)
   elseif leaf_type == "inet:ipv4-address" then
      box = helpers.IPv4Box.new()
   elseif leaf_type == "inet:ipv6-address" then
      box = helpers.IPv6Box.new()
   else
      local path = self and getmetatable(self).path or ""
      error(("Unknown type '%s' for leaf"):format(path, leaf_type))
   end

   return box
end

-- Yang feature
local Feature = {}
function Feature.new(base, path, src)
   local self = setmetatable({}, {__index=Feature, path=path})

   self:validate_schema(src)
   base:add_cache(path, self)

   if src.description then
      self.description = src.description[1].argument
   end

   if src.reference then
      self.reference = src.reference[1].argument
   end

   if src.status then
      self.status = src.reference[1].argument
   end

   return self
end

function Feature:validate_schema(src)
   local cardinality = {description={0,1}, status={0,1}, refernece={0,1}}
   validation.cardinality("feature", getmetatable(self).path, cardinality, src)
end

-- Yang list
local List = {}
function List.new(base, path, src)
   local self = setmetatable({}, {__index=List, path=path})

   self:validate_schema(src)
   base:add_cache(path, self)

   if src.key then self.key = src.key[1].argument end
   if src.leaf then
      for _, leaf in pairs(src.leaf) do
         local path = self.path.."."..leaf.argument
         self[leaf.argument] = Leaf.new(base, path, leaf.statements)
      end
   end

   return self
end

function List:validate_schema(src)
   local cardinality = {config={0,1}, description={0,1}, key={0,1},
                        reference={0,1}, status={0,1}, when={0,1}}
   cardinality["max-elements"] = {0,1}
   cardinality["min-elements"] = {0,1}
   cardinality["ordered-by"] = {0,1}
   validation.cardinality("list", getmetatable(self).path, cardinality, src)
end

-- Yang group
local Grouping = {}
function Grouping.new(base, path, src)
   local ret = {leaves={}}
   local self = setmetatable(ret, {__index = Grouping, path=path})

   self:validate_schema(src)
   base:add_cache(path, self)

   if src.description then
      self.description = src.description[1].argument
   end

   if src.list then
      for _, list in pairs(src.list) do
         local path = path.."."..list.argument
         self[list.argument] = List.new(base, path, list.statements)
      end
   end

   if src.leaf then
      for _, leaf in pairs(src.leaf) do
         local path = path.."."..leaf.argument
         self.leaves[leaf.argument] = Leaf.new(base, path, leaf.statements)
      end
   end

   return self
end

function Grouping:validate_schema(src)
   local cardinality = {description={0,1}, reference={0,1}, status={0,1}}
   validation.cardinality("grouping", getmetatable(self).path, cardinality, src)
end

local Container = {}
function Container.new(base, path, src)
   local ret = {leaves={}, containers={}}
   local self = setmetatable(ret, {__index=Container, path=path})

   self:validate_schema(src)
   base:add_cache(path, self)

   if src.description then
      self.description = src.description[1].argument
   end

   -- Leaf statements
   if src.leaf then
      for _, leaf in pairs(src.leaf) do
         local leaf_path = path.."."..leaf.argument
         self.leaves[leaf.argument] = Leaf.new(base, leaf_path, leaf.statements)
      end
   end

   -- Include other containers
   if src.container then
      for _, container in pairs(src.container) do
         local container_path = path.."."..container.argument
         self.containers[container.argument] = Container.new(
            base,
            container_path,
            container.statements
         )
      end
   end

   if src.uses then
      self.uses = src.uses[1].argument
   end

   return self
end

function Container:validate_schema(src)
   local cardinality = {config={0,1}, description={0,1}, presense={0,1},
                        reference={0,1}, status={0,1}, when={0,1}}
   validation.cardinality("container", getmetatable(self).path, cardinality, src)
end

-- Yang Revision
local Revision = {}
function Revision.new(base, path, src)
   local self = setmetatable({}, {__index=Revision, path=path})

   self:validate_schema(src)
   base:add_cache(path, self)

   if src.description then
      self.description = src.description[1].argument
   end

   if src.reference then
      self.reference = src.reference[1].argument
   end
   return self
end

function Revision:validate_schema(src)
   local cardinality = {description={0,1}, reference={0,1}}
   validation.cardinality("revision", getmetatable(self).path, cardinality, src)
end

-- Yang Module
Module = {}
function Module.new(base, name, src)
   local ret = {body={}, name=name, modules={}, revisions={},
               features={}, groupings={}, containers={}}
   local self = setmetatable(ret, {__index=Module, path=name})

   -- TODO: remove me when proper loading support exists.
   if not src then return self end

   -- Add self to path cache
   base:add_cache(name, self)

   -- Validate the statements first.
   self:validate_schema(src)

   -- Set the meta information about the module
   self.namespace = src.namespace[1].argument
   self.prefix = src.prefix[1].argument

   if src.organization then
      self.organization = src.organization[1].argument
   end

   if src.contact then
      self.contact = src.contact[1].argument
   end

   if src.description then
      self.description = src.description[1].argument
   end
  
   -- Now handle the imports, as other things may reference them.
   if src.import then
      for _, mod in pairs(src.import) do
         self.modules[mod.argument] = Module.new(base, mod.argument)

         -- Ask the module to find and load itself.
         self.modules[mod.argument]:load()
      end
   end

   -- Handle revisions
   if src.revision then
      for _, r in pairs(src.revision) do
         local path = ret.name.."."..r.argument
         self.revisions[r.argument] = Revision.new(base, path, r.statements)
      end
   end

   -- Feature statements
   if src.feature then
      for _, f in pairs(src.feature) do
         local path = ret.name.."."..f.argument
         self.features[f.argument] = Feature.new(base, path, f.statements)
      end
   end

   -- List statements
   if src.grouping then
      for _, g in pairs(src.grouping) do
         local path = ret.name.."."..g.argument
         self.groupings[g.argument] = Grouping.new(base, path, g.statements)
      end
   end

   -- Containers
   if src.container then
      for _, c in pairs(src.container) do
         local path = ret.name.."."..c.argument
         self.containers[c.argument] = Container.new(base, path, c.statements)
      end
   end
   return self
end

function Module:load()
   -- TODO: Find the file and load it.
end

function Module:validate_schema(src)
   local cardinality = {contact={0,1}, description={0,1}, namespace={1,1},
                        organization={0,1}, prefix={1,1}, reference={0,1}}
   cardinality["yang-version"] = {0,1}
   validation.cardinality("module", getmetatable(self).path, cardinality, src)
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
         description "Version-02: Add notifications.";
         reference "tbc";
      }

      revision 2015-02-06 {
         description
            "Version-01: Correct grammar errors; Reuse groupings; Update
            descriptions.";

         reference "tbc";
      }

      revision 2015-02-02 {
         description "Initial revision.";
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

         reference "I-D.ietf-softwire-lw4over6";
      }

      feature map-e {
         description
            "MAP-E is a mechanism for transporting IPv4 packets across an
            IPv6 network using IP encapsulation, and a generic mechanism
            for mapping between IPv6 addresses and IPv4 addresses and
            transport layer ports.";

         reference "I-D.ietf-softwire-map";
      }

      grouping port-set {
         description
            "Use the PSID algorithm to represent a range of transport layer
            ports.";

         leaf offset {
            type uint8 {
               range 0..16;
            }
            mandatory true;
            description
               "The number of offset bits. In Lightweight 4over6, the default
               value is 0 for assigning one contiguous port range. In MAP-E/T,
               the default value is 6, which excludes system ports by default
               and assigns distributed port ranges. If the this parameter is
               larger than 0, the value of offset MUST be greater than 0.";
         }

         leaf psid {
            type uint16;
            mandatory true;
            description
               "Port Set Identifier (PSID) value, which identifies a set
               of ports algorithmically.";
         }

         leaf psid-len {
            type uint8 {
               range 0..16;
            }
            mandatory true;
            description
               "The length of PSID, representing the sharing ratio for an
               IPv4 address.";
         }
      }

      container softwire-config {
         description
            "The configuration data for Softwire instances. And the shared
            data describes the softwire data model which is common to all of
            the different softwire mechanisms, such as description.";

         leaf description {
            type string;
            description "A textual description of Softwire.";
         }
      }
   }]]

  -- Convert the schema using the already tested parser.
  local parser = require("lib.yang.parser")
  local schema = parser.parse_string(test_schema, "schema selftest")

  -- Create a fake base, we're not testing this so avoidng using the real one.
  local base = {add_cache = function() end}

  -- Convert the schema into a more usable form for us.
  schema = helpers.extract_nodes(schema)
  
  -- Load the module 
  local mod = Module.new(base, schema.module[1].argument,
    schema.module[1].statements)

  assert(mod.name == "ietf-softwire")
  assert(mod.namespace == "urn:ietf:params:xml:ns:yang:ietf-softwire")
  assert(mod.prefix == "softwire")
  assert(mod.contact)
  assert(mod.organization)
  assert(mod.description)

  -- Check both modules exist. (Also need to check they've loaded)
  assert(mod.modules["ietf-inet-types"])
  assert(mod.modules["ietf-yang-types"])

  -- Check all revisions are accounted for.
  assert(mod.revisions["2015-02-02"].description)
  assert(mod.revisions["2015-02-06"].description)
  assert(mod.revisions["2015-02-10"].description)
  assert(mod.revisions["2015-04-07"].description)
  assert(mod.revisions["2015-09-30"].description)

  -- Check that the feature statements are there.
  assert(mod.features["lw4over6"].description)
  assert(mod.features["lw4over6"].reference)
  assert(mod.features["map-e"].description)
  assert(mod.features["map-e"].reference)

  -- Check the groupings
  assert(mod.groupings["port-set"])
  assert(mod.groupings["port-set"].description)
  assert(mod.groupings["port-set"].leaves["offset"])
  assert(mod.groupings["port-set"].leaves["offset"].type == "uint8")
  assert(mod.groupings["port-set"].leaves["psid-len"].mandatory == true)
  assert(mod.groupings["port-set"].leaves["psid-len"].range[1] == 0)
  assert(mod.groupings["port-set"].leaves["psid-len"].range[2] == 16)

  -- Check the containers description (NOT the leaf called "description")
  assert(type(mod.containers["softwire-config"].description) == "string")

  -- Check the container has a leaf called "description"
  assert(mod.containers["softwire-config"].leaves.description)
end