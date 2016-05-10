-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

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

Container = {}
function Container.new(base, path)
   local ret = {root={}, base=base, path=path}
   return setmetatable(ret, {
      __newindex = function (t, k, v)
         -- Validate the value prior to setting it.
         local schema = ret.base:get_schema(ret.path.."."..k)
         if schema.validation then
            for _, validation in pairs(schema.validation) do
               validation(v)
            end
         end

         local box = ret.root[k]
         if box == nil then error("Unknown leaf '"..k.."'") end
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