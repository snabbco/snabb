-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
-- This is the entry-point to the lua YANG library. It will handle parsing a
-- file with YANG statements and producing a schema tree and data tree.
--
-- To use this you should use the helper functions:
--    - load_schema
--    - load_schema_file
-- The former takes in a yang string and builds a Base table, similarly the
-- load_schema_file takes a schema file and builds a Base table from that.
--
-- Once you have the base file you can inspect the schema, data and set values.
-- Example:
--    local base = load_schema[[
--      module example {
--        namespace "exampleinc:example";
--        prefix "example";
--        organization "Example Inc.";
--        description "An example document"
--
--        container conf {
--          leaf description {
--            type string;
--          }
--          leaf testvalue {
--            type uint8;
--          }
--        }
--      }]]
--    base["example"].organization == "YANG IPv4 over IPv6"
--    base["example"].containers["conf"].leaves["description"].type == "string"
--    
--    -- Setting data
--    base.data["example"]["conf"].description = "hello!"
--    base.data["example"]["conf"].testvalue = "error" -- This errors.
--    base.data["example"]["conf"].testvalue = 50000 -- Beware: they overflow.
module(..., package.seeall)

local schema = require("lib.yang.schema")
local helpers = require("lib.yang.helpers")
local parser = require("lib.yang.parser")
local Container = helpers.Container
local asserterror = helpers.asserterror
local setvalue = helpers.setvalue

Base = {}
function Base.new(filename)
   local ret = {schema={}, filename=filename}
   local self = setmetatable(ret, {__index=Base, path_cache={}})
   self.data = Container.new(self, "")
   return self
end

function Base:error(path, node, msg, ...)
   error(("Error: %s.%s: %s"):format(path, node, (msg):format(...)))
end

function Base:load(src)
   src = helpers.extract_nodes(src)
   if not src.module then
      error(("%s: Expected 'module'"):format(self.filename))
   end
   local mod = schema.Module.new(
      self,
      src.module[1].argument,
      src.module[1].statements
   )
   self.schema[src.module[1].argument] = mod

   self.data:add_container(mod.name)
   return self.schema
end

function Base:get_schema(path)
   -- Handle case when path is empty. (Provide with self.data)
   if path == "" then
      return self.data
   end

   -- Look in the cache and hopefully return the schema node for the path.
   local cache = getmetatable(self).path_cache
   return cache[path]
end

function Base:add_cache(path, node)
   getmetatable(self).path_cache[path] = node
end

function Base:get_module()
   local schema_mod
   for _, mod in pairs(self.schema) do
      schema_mod = mod
   end

   if not schema_mod then
      error("Module cannot be resolved")
   end

   return schema_mod
end

function Base:produce_data_tree(schema_node, data_node)
   if not (schema_node and data_node) then
      schema_node = self:get_module()

      if not schema_node then error("Module cannot be resolved") end
      data_node = self.data[schema_node.name]
   end
   path = getmetatable(schema_node).path

   if schema_node.containers then
      for name, container in pairs(schema_node.containers) do
         local new_path = path.."."..name
         local new_node = Container.new(self, new_path)

         data_node:add_to_root(name, new_node)
         schema_node = self:get_schema(new_path)
         data_node = new_node
         self:produce_data_tree(schema_node, new_node)

         -- If the container has a "uses" statement we must copy across the 
         -- leaves from the container it references to this container.
         if container.uses then
            self:handle_use(container, data_node, path, name)
         end
      end
   end

   if schema_node.leaves then
      for name, leaf in pairs(schema_node.leaves) do
         data_node:add_to_root(name, leaf:provide_box())
      end
   end

   if schema_node.lists then
      for name, list in pairs(schema_node.lists) do
         local list_path = path.."."..name
         local container = Container.new(self, list_path)
         data_node:add_to_root(name, container)

         if list.uses then
            local template = Container.new(self, list_path)
            self:handle_use(list, template, list_path, name)
            container:set_template(template)
         end
      end
   end

   return self.data
end

function Base:schema_for_uses(schema)
   if schema.uses == nil then
      error("Can only find schema for a node which uses the `use` statement.")
   end

   return self:get_module().groupings[schema.uses]
end

function Base:handle_use(schema_node, data_node, path, name)
   local grouping = self:schema_for_uses(schema_node)
   if not grouping then
      self:error(path, name, "Cannot find grouping '%s'.", schema_node.uses)
   end

   -- Copy.
   for name, leaf in pairs(grouping.leaves) do
      -- We also need to register the schema node at the new path
      local grouping_path = path.."."..name
      self:add_cache(grouping_path, leaf)
      data_node:add_to_root(name, leaf:provide_box())
   end
end

function Base:add(key, node)
   self.data[key] = node
end

function load_schema(schema, filename)
   local parsed_yang = parser.parse_string(schema, "selftest")
   local base = Base.new()
   base:load(parsed_yang)
   return base
end

function load_schema_file(filename)
   local file_in = assert(io.open(filename))
   local contents = file_in:read("*a")
   file_in:close()
   return load_schema(contents, filename)
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
   local base = load_schema(test_schema)
   local data = base:produce_data_tree()
   local bowl = data.fruit["fruit-bowl"]

   bowl.description = "hello!"
   assert(bowl.description == "hello!")

   -- Add items to fruit-bowl's contents list.
   bowl.contents:add_item({name="Banana", score=10})
   assert(bowl.contents[1].name == "Banana")
   assert(bowl.contents[1].score == 10)

   -- Check that validation still works in lists with groupings.
   asserterror(setvalue, bowl.contents[1].score, "fail")

   -- Check that an entry can't be added with missing required fields
   asserterror(bowl.contents.add_item, bowl.contents, {score=10})

   -- Check that an entry with incorrect data can't be added.
   asserterror(
      bowl.contents.add_item,
      bowl.contents,
      {name="Pear", score=5, invalid=true}
   )

   -- Finally check tht validation occurs when you're adding entries with
   -- invalid data in them, in this case sore needs to be an integer.
   asserterror(bowl.contents, bowl.contents, {name="Pear", score="Good"})
end