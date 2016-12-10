module(..., package.seeall)

--local S = require("syscall")
--local snabb_cmd = ("/proc/%d/exe"):format(S.getpid())

local schema = require("lib.yang.schema")
local softwire_schema = schema.load_schema_by_name("snabb-softwire-v1")

function generate_get(pid)
   local query = generate_xpath(softwire_schema)
   return string.format("./snabb config get %s \"%s\"", pid, query)
end

function generate_get_state(pid)
   local query = generate_xpath_state(softwire_schema, true)
   return string.format("./snabb config get-state %s \"%s\"", pid, query)
end

function generate_set(pid, val)
   local query = generate_xpath(softwire_schema)
   return string.format("./snabb config set %s \"%s\" \"%s\"", pid, query, val)
end

function run_yang(yang_cmd)
   local f = io.popen(yang_cmd)
   local result = f:read("*a")
   f:close()
   return result
end

-- choose an element of an array randomly
local function choose(choices)
   local idx = math.random(#choices)
   return choices[idx]
end

-- choose from unbounded array indices, decreasing likelihood
local function choose_pos()
   local r = math.random()

   local function flip(next)
      local r = math.random()
      if r < 0.5 then
         return next
      else
         return flip(next + 1)
      end
   end

   -- evenly weight first five indices
   if r < 0.5 then
      return choose({1, 2, 3, 4, 5})
   else
      return flip(6)
   end
end

function generate_xpath_state()
   return generate_xpath(softwire_schema.body["softwire-state"])
end

-- from a config schema, generate an xpath query string
-- this code is patterned off of the visitor used in lib.yang.data
function generate_xpath(schema)
   local path = ""
   local handlers = {}

   local function visit(node)
      local handler = handlers[node.kind]
      if handler then handler(node) end
   end
   local function visit_body(node)
      local ids = {}
      for id, node in pairs(node.body) do
         -- only choose nodes that are used in configs
         if node.config ~= false then
            table.insert(ids, id)
         end
      end

      local id = choose(ids)
      if id then
         visit(node.body[id])
      end
   end
   function handlers.container(node)
      path = path .. "/" .. node.id

      -- don't always go into containers, since we need to test
      -- fetching all sub-items too
      if math.random() < 0.9 then
         visit_body(node)
      end
   end
   handlers['leaf-list'] = function(node)
      local selector = string.format("[position()=%d]", choose_pos())
      path = path .. "/" .. node.id .. selector
   end
   function handlers.list(node)
      -- TODO: this should generate selector-based lookups by using
      --       the key type as a generation source, but for now do
      --       the simple thing
      path = path .. "/" .. node.id
   end
   function handlers.leaf(node)
      path = path .. "/" .. node.id
   end

   -- just produce "/" on rare occasions
   if math.random() > 0.01 then
      visit_body(schema)
   end

   return path
end

function selftest()
   local data = require("lib.yang.data")
   local path = require("lib.yang.path")
   local grammar = data.data_grammar_from_schema(softwire_schema)

   path.convert_path(grammar, generate_xpath(softwire_schema))
end
