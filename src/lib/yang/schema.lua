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

local helpers = require("lib.yang.helpers")
local h = require("syscall.helpers")

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
      elseif self.type == "union" and typeinfo.type then
         self.types = {}
         for _, v in pairs(typeinfo.type) do
            self.types[#self.types + 1] = v.argument
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
            self:error("Value '%s' is out of range", path, v)
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

function Leaf:get_type() return "leaf" end

function Leaf:error(msg, ...)
   local path = getmetatable(self).path
   error(("%s: %s"):format(path, msg:format(...)))
end

function Leaf:validate_schema(schema)
   local cardinality = {config={0,1}, default={0,1}, description={0,1},
                        mandatory={0,1}, reference={0,1}, status={0,1},
                        type={1,1}, units={0,1}, when={0,1}}
   helpers.cardinality("leaf", getmetatable(self).path, cardinality, schema)
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

function Feature:get_type() return "feature" end

function Feature:validate_schema(src)
   local cardinality = {description={0,1}, status={0,1}, refernece={0,1}}
   helpers.cardinality("feature", getmetatable(self).path, cardinality, src)
end

-- Yang list
local List = {}
function List.new(base, path, src)
   local ret = {leaves={}}
   local self = setmetatable(ret, {__index=List, path=path})

   self:validate_schema(src)
   base:add_cache(path, self)

   if src.key then self.key = src.key[1].argument end
   if src.uses then self.uses = src.uses[1].argument end
   if src.leaf then
      for _, leaf in pairs(src.leaf) do
         local path = self.path.."."..leaf.argument
         self.leaves[leaf.argument] = Leaf.new(base, path, leaf.statements)
      end
   end

   return self
end
function List:get_type() return "list" end

function List:validate_schema(src)
   local cardinality = {config={0,1}, description={0,1}, key={0,1},
                        reference={0,1}, status={0,1}, when={0,1}}
   cardinality["max-elements"] = {0,1}
   cardinality["min-elements"] = {0,1}
   cardinality["ordered-by"] = {0,1}
   helpers.cardinality("list", getmetatable(self).path, cardinality, src)
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
function Grouping:get_type() return "grouping" end

function Grouping:validate_schema(src)
   local cardinality = {description={0,1}, reference={0,1}, status={0,1}}
   helpers.cardinality("grouping", getmetatable(self).path, cardinality, src)
end

local Container = {}
function Container.new(base, path, src)
   local ret = {leaves={}, containers={}, lists={}}
   local self = setmetatable(ret, {__index=Container, path=path})

   self:validate_schema(src)
   base:add_cache(path, self)

   if src.description then
      self.description = src.description[1].argument
   end

   -- Leaf statements
   if src.leaf then
      for _, leaf in pairs(src.leaf) do
         self.leaves[leaf.argument] = Leaf.new(
            base,
            path.."."..leaf.argument,
            leaf.statements
         )
      end
   end

   -- Include other containers
   if src.container then
      for _, container in pairs(src.container) do
         self.containers[container.argument] = Container.new(
            base,
            path.."."..container.argument,
            container.statements
         )
      end
   end

   if src.list then
      for _, list in pairs(src.list) do
         self.lists[list.argument] = List.new(
            base,
            path.."."..list.argument,
            list.statements
         )
      end
   end

   if src.uses then
      self.uses = src.uses[1].argument
   end

   return self
end
function Container:get_type() return "container" end

function Container:validate_schema(src)
   local cardinality = {config={0,1}, description={0,1}, presense={0,1},
                        reference={0,1}, status={0,1}, when={0,1}}
   helpers.cardinality("container", getmetatable(self).path, cardinality, src)
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
function Revision:get_type() return "revision" end

function Revision:validate_schema(src)
   local cardinality = {description={0,1}, reference={0,1}}
   helpers.cardinality("revision", getmetatable(self).path, cardinality, src)
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
function Module:get_type() return "module" end

function Module:load()
   -- TODO: Find the file and load it.
end

function Module:validate_schema(src)
   local cardinality = {contact={0,1}, description={0,1}, namespace={1,1},
                        organization={0,1}, prefix={1,1}, reference={0,1}}
   cardinality["yang-version"] = {0,1}
   helpers.cardinality("module", getmetatable(self).path, cardinality, src)
end

function selftest()
   local test_schema = [[module fruit {
      namespace "urn:testing:fruit";
      prefix "fruit";

      import ietf-inet-types {prefix inet; }
      import ietf-yang-types {prefix yang; }

      organization "Fruit Inc.";

      contact "John Smith fake@person.tld";

      description "Module to test YANG schema lib";

      revision 2016-05-27 {
         description "Revision 1";
         reference "tbc";
      }

      revision 2016-05-28 {
         description "Revision 2";
         reference "tbc";
      }

      feature bowl {
         description "A fruit bowl";
         reference "fruit-bowl";
      }

      grouping fruit {
         description "Represets a piece of fruit";

         leaf name {
            type string;
            mandatory true;
            description "Name of fruit.";
         }

         leaf score {
            type uint8 {
               range 0..10;
            }
            mandatory true;
            description "How nice is it out of 10";
         }

         leaf tree-grown {
            type boolean;
            description "Is it grown on a tree?";
         }
      }

      container fruit-bowl {
         description "Represents a fruit bowl";

         leaf description {
            type string;
            description "About the bowl";
         }

         list contents {
            uses fruit;
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

  assert(mod.name == "fruit")
  assert(mod.namespace == "urn:testing:fruit")
  assert(mod.prefix == "fruit")
  assert(mod.contact == "John Smith fake@person.tld")
  assert(mod.organization == "Fruit Inc.")
  assert(mod.description == "Module to test YANG schema lib")

  -- Check both modules exist. (Also need to check they've loaded)
  assert(mod.modules["ietf-inet-types"])
  assert(mod.modules["ietf-yang-types"])

  -- Check all revisions are accounted for.
  assert(mod.revisions["2016-05-27"].description == "Revision 1")
  assert(mod.revisions["2016-05-28"].description == "Revision 2")

  -- Check that the feature statements are there.
  assert(mod.features["bowl"].description)

  -- Check the groupings
  assert(mod.groupings["fruit"])
  assert(mod.groupings["fruit"].description)
  assert(mod.groupings["fruit"].leaves["name"].type == "string")
  assert(mod.groupings["fruit"].leaves["name"].mandatory == true)
  assert(mod.groupings["fruit"].leaves["name"].description == "Name of fruit.")
  assert(mod.groupings["fruit"].leaves["score"].type == "uint8")
  assert(mod.groupings["fruit"].leaves["score"].mandatory == true)
  assert(mod.groupings["fruit"].leaves["score"].range[1] == 0)
  assert(mod.groupings["fruit"].leaves["score"].range[2] == 10)

  -- Check the containers description (NOT the leaf called "description")
  assert(mod.containers["fruit-bowl"].description == "Represents a fruit bowl")

  -- Check the container has a leaf called "description"
  local desc = mod.containers["fruit-bowl"].leaves.description
  assert(desc.type == "string")
  assert(desc.description == "About the bowl")
end