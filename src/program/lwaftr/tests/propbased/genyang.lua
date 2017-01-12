module(..., package.seeall)

-- This module provides functions for generating snabb config
-- commands with random path queries and values

local schema = require("lib.yang.schema")

local capabilities = {['ietf-softwire']={feature={'binding', 'br'}}}
require('lib.yang.schema').set_default_capabilities(capabilities)

local schemas = { "ietf-softwire", "snabb-softwire-v1" }

-- Generate a get/set command string given a pid string and optional schema
function generate_get_or_set(pid, schema)
   local r = math.random()
   if r > 0.5 then
      local query, schema = generate_config_xpath(schema)
      return string.format("./snabb config get -s %s %s \"%s\"", schema, pid, query)
   else
      local query, val, schema = generate_config_xpath_and_val(schema)
      return string.format("./snabb config set -s %s %s \"%s\" \"%s\"",
                           schema, pid, query, val)
   end
end

-- Generate a get command string given a pid string and optional schema/query
function generate_get(pid, schema, query)
   if not query then
      query, schema = generate_config_xpath(schema)
   end
   return string.format("./snabb config get -s %s %s \"%s\"", schema, pid, query)
end

-- Like generate_get but for state queries
function generate_get_state(pid, schema, query)
   if not query then
      query, schema = generate_config_xpath_state(schema)
   end
   return string.format("./snabb config get-state -s %s %s \"%s\"", schema, pid, query)
end

-- Used primarily for repeating a set with a value seen before from a get
function generate_set(pid, schema, query, val)
   return string.format("./snabb config set -s %s %s \"%s\" \"%s\"",
                        schema, pid, query, val)
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

-- choose a natural number (e.g., index or length of array) by
-- repeating a cointoss
local function choose_nat()
   local r = math.random()

   local function flip(next)
      local r = math.random()
      if r < 0.5 then
         return next
      else
         return flip(next + 1)
      end
   end

   -- evenly weight first two
   if r < 0.5 then
      return choose({1, 2})
   else
      return flip(3)
   end
end

local function random_hex()
  return string.format("%x", math.random(0, 15))
end

local function random_hexes()
   local str = ""
   for i=1, 4 do
      str = str .. random_hex()
   end
   return str
end

-- return a random number, preferring boundary values
local function choose_range(lo, hi)
   local r = math.random()
   if r < 0.1 then
      local mid = math.ceil((hi + lo) / 2)
      return choose({ 0, lo, lo + 1, mid, mid +  1,  hi - 1, hi })
   else
      return math.random(lo, hi)
   end
end

local function value_from_type(a_type)
   local prim = a_type.primitive_type

   if prim == "int8" then
      return choose_range(-128, 127)
   elseif prim == "int16" then
      return choose_range(-32768, 32767)
   elseif prim == "int32" then
      return choose_range(-2147483648, 2147483647)
   elseif prim == "int64" then
      return choose_range(-9223372036854775809, 9223372036854775807)
   elseif prim == "uint8" then
      return choose_range(0, 255)
   elseif prim == "uint16" then
      return choose_range(0, 65535)
   elseif prim == "uint32" then
      return choose_range(0, 4294967295)
   elseif prim == "uint64" then
      return choose_range(0, 18446744073709551615)
   elseif prim == "decimal64" then
      local int64 = value_from_type({ primitive_type="int64" })
      local exp   = math.random(1, 18)
      -- see RFC 6020 sec 9.3.1 for lexical representation
      return string.format("%f", int64 * (10 ^ -exp))
   elseif prim == "boolean" then
      return choose({ true, false })
   elseif prim == "ipv4-address" then
      return math.random(0, 255) .. "." .. math.random(0, 255) .. "." ..
             math.random(0, 255) .. "." .. math.random(0, 255)
   elseif prim == "ipv6-address" then
      local addr = random_hexes()
      for i=1, 7 do
          addr = addr .. ":" .. random_hexes()
      end
      return addr
   elseif prim == "ipv6-prefix" then
      local addr = value_from_type({ primitive_type = "ipv6-address" })
      return addr .. "/" .. math.random(0, 128)
   elseif prim == "mac-address" then
      local addr = random_hex() .. random_hex()
      for i=1,5 do
         addr = addr .. ":" .. random_hex() .. random_hex()
      end
      return addr
   elseif prim == "union" then
      return value_from_type(choose(a_type.union))
   elseif prim == "string" then
      local len = choose_nat()
      -- just ascii for now
      local str = ""
      for i=0, len do
         str = str .. string.char(math.random(97, 122))
      end
      return str
   elseif prim == "binary" then
      -- TODO: if restricted with length statement this should pick based
      --       on the octet length instead and introduce padding chars
      --       if necessary
      local encoded = ""
      local encoded_len = choose_nat() * 4

      for i=1, encoded_len do
         local r = math.random(0, 63)
         local byte

         if r <= 25 then
            byte = string.byte("A") + r
         elseif r > 25 and r <= 51 then
            byte = string.byte("a") + r-26
         elseif r > 51 and r <= 61 then
            byte = string.byte("0") + r-52
         elseif r == 63 then
            byte = string.byte("+")
         else
            byte = string.byte("/")
         end

         encoded = encoded .. string.char(byte)
      end

      return encoded
   end

   -- TODO: generate these:
   -- bits
   -- empty
   -- enumeration
   -- identityref
   -- instance-identifier
   -- leafref

   -- unknown type
   return nil
end

-- from a config schema, generate an xpath query string
-- this code is patterned off of the visitor used in lib.yang.data
local function generate_xpath_and_last_node(schema, for_state)
   local path = ""
   local handlers = {}
   local last_node

   local function visit(node)
      local handler = handlers[node.kind]
      if handler then handler(node) end
   end
   local function visit_body(node)
      local ids = {}
      for id, node in pairs(node.body) do
         -- only choose nodes that are used in configs unless
         -- for_state is passed
         if for_state or node.config ~= false then
            table.insert(ids, id)
         end
      end

      local id = choose(ids)
      if id then
         visit(node.body[id])
      else
         last_node = node
      end
   end
   function handlers.container(node)
      path = path .. "/" .. node.id

      -- don't always go into containers, since we need to test
      -- fetching all sub-items too
      if math.random() < 0.9 then
         visit_body(node)
      else
         last_node = node
      end
   end
   handlers['leaf-list'] = function(node)
      local selector = string.format("[position()=%d]", choose_nat())
      path = path .. "/" .. node.id .. selector
      last_node = node
   end
   function handlers.list(node)
      local key_types = {}
      local r = math.random()

      path = path .. "/" .. node.id

      -- occasionally drop the selectors
      if r < 0.9 then
         for key in (node.key):split(" +") do
            key_types[key] =  node.body[key].type
         end

         for key, type in pairs(key_types) do
            local val = assert(value_from_type(type), type.primitive_type)
            path = path .. string.format("[%s=%s]", key, val)
         end
      end

      if math.random() < 0.9 then
         visit_body(node)
      else
         last_node = node
      end
   end
   function handlers.leaf(node)
      path = path .. "/" .. node.id
      val  = value_from_type(node.type)
      last_node = node
   end

   -- just produce "/" on rare occasions
   if math.random() > 0.01 then
      visit_body(schema)
   end

   return path, last_node
end

-- similar to generating a query path like the function above, but
-- generates a compound value for `snabb config set` at some schema
-- node
local function generate_value_for_node(node)
   local handlers = {}

   local function visit(node)
      local handler = handlers[node.kind]
      if handler then return handler(node) end
   end
   local function visit_body(node)
      local ids = {}
      for id, node in pairs(node.body) do
         -- only choose nodes that are used in configs
         if node.config ~= false then
            table.insert(ids, id)
         end
      end

      local val = ""
      for _, id in ipairs(ids) do
         local subnode = node.body[id]
         local r = math.random()
         if subnode.mandatory or r > 0.5 then

            if subnode.kind == "leaf-list" then
               local count = choose_nat()
               for i=0, count do
                  local subval = visit(subnode)
                  val = val .. string.format("%s %s; ", id, subval)
               end
            elseif subnode.kind == "container" or subnode.kind == "list" then
               local subval = visit(subnode)
               val = val .. string.format("%s {%s} ", id, subval)
            else
               local subval = visit(subnode)
               val = val .. string.format("%s %s; ", id, subval)
            end
         end
      end

      return val
   end
   function handlers.container(node)
      return visit_body(node)
   end
   handlers['leaf-list'] = function(node)
      return value_from_type(node.type)
   end
   function handlers.list(node)
      -- FIXME: this will sometimes include a value for the list keys
      --        which isn't valid when the query path sets the keys
      return visit_body(node)
   end
   function handlers.leaf(node)
      return value_from_type(node.type)
   end

   return visit(node)
end

local function generate_xpath(schema, for_state)
   local path = generate_xpath_and_last_node(schema, for_state)
   return path
end

local function generate_xpath_and_val(schema)
   local val, path, last

   while not val do
      path, last = generate_xpath_and_last_node(schema)

      if last then
         val = generate_value_for_node(last)
      end
   end

   return path, val
end

function generate_config_xpath(schema_name)
   if not schema_name then
      schema_name = choose(schemas)
   end
   local schema      = schema.load_schema_by_name(schema_name)
   return generate_xpath(schema, false), schema_name
end

function generate_config_xpath_and_val(schema_name)
   if not schema_name then
      schema_name = choose(schemas)
   end
   local schema = schema.load_schema_by_name(schema_name)
   local path, val = generate_xpath_and_val(schema)
   return path, val, schema_name
end

function generate_config_xpath_state(schema_name)
   if not schema_name then
      schema_name = choose(schemas)
   end
   local schema      = schema.load_schema_by_name(schema_name)
   local path = generate_xpath(schema.body["softwire-state"], true)
   return "/softwire-state" .. path, schema_name
end

function selftest()
   local data = require("lib.yang.data")
   local path = require("lib.yang.path")
   local schema = schema.load_schema_by_name("snabb-softwire-v1")
   local grammar = data.data_grammar_from_schema(schema)

   path.convert_path(grammar, generate_xpath(schema))

   -- ensure decimal64 values match the right regexp
   for i=1, 100 do
      local val = value_from_type({ primitive_type="decimal64" })
      assert(string.match(val, "^-?%d+[.]%d+$"), string.format("test value: %s", val))
   end

   -- ensure generated base64 values are decodeable
   for i=1, 100 do
      local val = value_from_type({ primitive_type="binary" })
      local cmd = string.format("echo \"%s\" | base64 -d > /dev/null", val)
      assert(os.execute(cmd) == 0, string.format("test value: %s", val))
   end
end
