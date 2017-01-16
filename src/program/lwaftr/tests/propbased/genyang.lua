module(..., package.seeall)

-- This module provides functions for generating snabb config
-- commands with random path queries and values

local schema = require("lib.yang.schema")

local capabilities = {['ietf-softwire']={feature={'binding', 'br'}}}
require('lib.yang.schema').set_default_capabilities(capabilities)

local schemas = { "ietf-softwire", "snabb-softwire-v1" }

-- choose an element of an array randomly
local function choose(choices)
   local idx = math.random(#choices)
   return choices[idx]
end

-- Generate a get/set/add/remove string given a pid string and optional schema
function generate_any(pid, schema)
   local cmd = choose({ "get", "add", "remove", "set" })

   if cmd == "get" then
      local query, schema = generate_config_xpath(schema)
      return string.format("./snabb config get -s %s %s \"%s\"", schema, pid, query)
   elseif cmd == "set" then
      local query, val, schema = generate_config_xpath_and_val(schema)
      return string.format("./snabb config set -s %s %s \"%s\" \"%s\"",
                           schema, pid, query, val)
   elseif cmd == "add" then
      local query, val, schema = generate_config_xpath_and_val(schema)
      return string.format("./snabb config add -s %s %s \"%s\" \"%s\"",
                           schema, pid, query, val)
   else
      local query, schema = generate_config_xpath(schema)
      return string.format("./snabb config remove -s %s %s \"%s\"",
                           schema, pid, query)
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

-- return a random number, preferring boundary values and
-- sometimes returning results out of range
local function choose_bounded(lo, hi)
   local r = math.random()
   -- occasionally return values that are invalid for type
   -- to provoke crashes
   if r < 0.05 then
      local off = math.random(1, 100)
      return choose({ lo - off, hi + off })
   elseif r < 0.15 then
      local mid = math.ceil((hi + lo) / 2)
      return choose({ lo, lo + 1, mid, mid +  1,  hi - 1, hi })
   else
      return math.random(lo, hi)
   end
end

-- choose a random number, taking range statements into account
local function choose_range(rng, lo, hi)
   local r = math.random()

   if #rng == 0 or r < 0.1 then
      return choose_bounded(lo, hi)
   elseif rng[1] == "or" then
      local intervals = {}
      local num_intervals = (#rng - 1) / 2

      for i=1, num_intervals do
         intervals[i] = { rng[2*i], rng[2*i+1] }
      end

      return choose_range(choose(intervals), lo, hi)
   else
      local lo_rng, hi_rng = rng[1], rng[2]

      if lo_rng == "min" then
         lo_rng = lo
      end
      if hi_rng == "max" then
         hi_rng = hi
      end

      return choose_bounded(math.max(lo_rng, lo), math.min(hi_rng, hi))
   end
end

local function value_from_type(a_type)
   local prim = a_type.primitive_type
   local rng

   if a_type.range then
      rng = a_type.range.value
   else
      rng = {}
   end

   if prim == "int8" then
      return choose_range(rng, -128, 127)
   elseif prim == "int16" then
      return choose_range(rng, -32768, 32767)
   elseif prim == "int32" then
      return choose_range(rng, -2147483648, 2147483647)
   elseif prim == "int64" then
      return choose_range(rng, -9223372036854775809, 9223372036854775807)
   elseif prim == "uint8" then
      return choose_range(rng, 0, 255)
   elseif prim == "uint16" then
      return choose_range(rng, 0, 65535)
   elseif prim == "uint32" then
      return choose_range(rng, 0, 4294967295)
   elseif prim == "uint64" then
      return choose_range(rng, 0, 18446744073709551615)
   -- TODO: account for fraction-digits and range
   elseif prim == "decimal64" then
      local int64 = math.random(-9223372036854775809, 9223372036854775807)
      local exp   = math.random(1, 18)
      -- see RFC 6020 sec 9.3.1 for lexical representation
      return string.format("%f", int64 * (10 ^ -exp))
   elseif prim == "boolean" then
      return choose({ true, false })
   elseif prim == "ipv4-address" then
      return math.random(0, 255) .. "." .. math.random(0, 255) .. "." ..
             math.random(0, 255) .. "." .. math.random(0, 255)
   elseif prim == "ipv6-address" or prim == "ipv6-prefix" then
      local addr = random_hexes()
      for i=1, 7 do
          addr = addr .. ":" .. random_hexes()
      end

      if prim == "ipv6-prefix" then
         return addr .. "/" .. math.random(0, 128)
      end

      return addr
   elseif prim == "mac-address" then
      local addr = random_hex() .. random_hex()
      for i=1,5 do
         addr = addr .. ":" .. random_hex() .. random_hex()
      end
      return addr
   elseif prim == "union" then
      return value_from_type(choose(a_type.union))
   -- TODO: follow pattern statement
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
   elseif prim == "empty" then
      return ""
   elseif prim == "enumeration" then
      local enum = choose(a_type.enums)
      return enum.value
   end

   -- TODO: these appear unused in the current YANG schemas so
   --       they're left out for now
   -- bits
   -- identityref
   -- instance-identifier
   -- leafref

   error("NYI or unknown type")
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

-- types that may be randomly picked for a fuzzed test case
local types = { "int8", "int16", "int32", "int64", "uint8", "uint16",
                "uint32", "uint64", "decimal64", "boolean", "ipv4-address",
                "ipv6-address", "ipv6-prefix", "mac-address", "string",
                "binary" }

function generate_config_xpath_and_val(schema_name)
   if not schema_name then
      schema_name = choose(schemas)
   end
   local schema = schema.load_schema_by_name(schema_name)
   local r = math.random()
   local path, val

   -- once in a while, generate a nonsense value
   if r < 0.05 then
     path = generate_xpath(schema, false)
     val = value_from_type({ primitive_type=choose(types) })
   else
     path, val = generate_xpath_and_val(schema)
   end

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

   -- check some int types with range statements
   for i=1, 100 do
      local val1 = value_from_type({ primitive_type="uint8",
                                     range={ value = {1, 16} } })
      local val2 = value_from_type({ primitive_type="uint8",
                                     range={ value = {"or", 1, 16, 18, 32} } })
      local val3 = value_from_type({ primitive_type="uint8",
                                     range={ value = {"or", "min", 10, 250, "max"} } })
      assert(val1 >= 1 and val1 <= 16, string.format("test value: %d", val1))
      assert(val2 >= 1 and val2 <= 32 and val2 ~= 17,
             string.format("test value: %d", val2))
      assert(val3 >= 0 and val3 <= 255 and not (val3 > 10 and val3 < 250),
             string.format("test value: %d", val3))
   end

   -- ensure decimal64 values match the right regexp
   for i=1, 100 do
      local val = value_from_type({ primitive_type="decimal64",
                                    range={ value={} } })
      assert(string.match(val, "^-?%d+[.]%d+$"), string.format("test value: %s", val))
   end

   -- ensure generated base64 values are decodeable
   for i=1, 100 do
      local val = value_from_type({ primitive_type="binary",
                                    range={ value={} }})
      local cmd = string.format("echo \"%s\" | base64 -d > /dev/null", val)
      assert(os.execute(cmd) == 0, string.format("test value: %s", val))
   end
end
