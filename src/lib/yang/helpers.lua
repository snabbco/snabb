-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

function split(delimiter, text)
   -- This is taken from syslog.
   if delimiter == "" then return {text} end
   if #text == 0 then return {} end
   local list = {}
   local pos = 1
   while true do
      local first, last = text:find(delimiter, pos)
      if first then
         list[#list + 1] = text:sub(pos, first - 1)
         pos = last + 1
      else
         list[#list + 1] = text:sub(pos)
         break
      end
   end
   return list
end

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
   local meta = {}
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

function selftest()
   local result = split("%.%.", "0..9")
   assert(result[1] == "0")
   assert(result[2] == "9")

   local result = split("%-", "hello-lua")
   assert(result[1] == "hello")
   assert(result[2] == "lua")
end