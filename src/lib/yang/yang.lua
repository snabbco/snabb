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

   -- TODO: don't use rawget here.
   local data_root = rawget(self.data, "root")
   data_root[mod.name] = Container.new(self, mod.name)
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

         -- TODO: change me, we shouldn't be using rawget here!
         local root = rawget(data_node, "root")
         root[name] = new_node
         schema_node = self:get_schema(new_path)
         data_node = new_node
         self:produce_data_tree(schema_node, new_node)

         -- If the container has a "uses" statement we must copy across the 
         -- leaves from the container it references to this container.
         if container.uses then
            local root = rawget(data_node, "root")
            local grouping = self:get_module().groupings[container.uses]
            if not grouping then
               self:error(path, name, "Cannot find grouping '%s'.", container.uses)
            end

            -- Copy.
            for name, leaf in pairs(grouping.leaves) do
               -- We also need to register the schema node at the new path
               local grouping_path = new_path.."."..name
               self:add_cache(grouping_path, leaf)
               root[name] = leaf:provide_box()
            end
         end
      end
   end

   if schema_node.leaves then
      for name, leaf in pairs(schema_node.leaves) do
         -- TODO remove the use of rawget here, it's not good.
         local root = rawget(data_node, "root")
         root[name] = leaf:provide_box()
      end
   end
   return self.data
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
   local test_yang = [[module ietf-softwire {
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
            "The number of offset bits. In Lightweight 4over6, the defaul
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

   grouping binding-entry {
      description
         "The lwAFTR maintains an address binding table that contains
         thebinding between the lwB4's IPv6 address, the allocated IPv4
         address and restricted port-set.";

      leaf binding-ipv6info {
         type union {
            type inet:ipv6-address;
            type inet:ipv6-prefix;
         }

         mandatory true;
         description
            "The IPv6 information for a binding entry.
            If it's an IPv6 prefix, it indicates that
            the IPv6 source address of the lwB4 is constructed
            according to the description in RFC7596;
            if it's an IPv6 address, it means the lwB4 uses";
      }

      leaf binding-ipv4-addr {
         type inet:ipv4-address;
         mandatory true;
         description
            "The IPv4 address assigned to the lwB4, which is
            used as the IPv4 external address
            for lwB4 local NAPT44.";
      }

      container port-set {
         description
            "For Lightweight 4over6, the default value
            of offset should be 0, to configure one contiguous
            port range.";
         uses port-set {
            refine offset {
               default "0";
            }
         }
      }

      leaf lwaftr-ipv6-addr {
         type inet:ipv6-address;
         mandatory true;
         description "The IPv6 address for lwaftr.";
      }

      leaf lifetime {
         type uint32;
         units seconds;
         description "The lifetime for the binding entry";
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

      container testgroup {
         uses binding-entry;
      }
   }
}]]
   local base = load_schema(test_yang)
   local data = base:produce_data_tree()

   data["ietf-softwire"]["softwire-config"].description = "hello!"
   assert(data["ietf-softwire"]["softwire-config"].description == "hello!")

   -- Test grouping.
   data["ietf-softwire"]["softwire-config"].testgroup["lifetime"] = 72
   assert(data["ietf-softwire"]["softwire-config"].testgroup["lifetime"] == 72)
end