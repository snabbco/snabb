module(..., package.seeall)

-- This module provides functions for generating snabb config
-- commands with random path queries and values

local ffi       = require("ffi")
local schema    = require("lib.yang.schema")
local data      = require("lib.yang.data")
local path_data = require("lib.yang.path_data")
local util      = require("lib.yang.util")

local capabilities = {['ietf-softwire-br']={feature={'binding'}},}
require('lib.yang.schema').set_default_capabilities(capabilities)

local schemas = { "ietf-softwire-br", "snabb-softwire-v3" }

-- choose an element of an array randomly
local function choose(choices)
   local idx = math.random(#choices)
   return choices[idx]
end

local function maybe(f, default, prob)
   return function(...)
      if math.random() < (prob or 0.8) then return f(...) end
      return default
   end
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
   -- use rejection sampling for add and remove commands to restrict to list or
   -- leaf-list cases (for remove, we need a case with a selector too)
   -- Note: this assumes a list or leaf-list case exists in the schema at all
   elseif cmd == "add" then
      local query, val, schema = generate_config_xpath_and_val(schema)
      return string.format("./snabb config add -s %s %s \"%s\" \"%s\"",
                           schema, pid, query, val)
   else
      local query, val, schema = generate_config_xpath_and_val(schema)
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
      query, schema = generate_state_xpath(schema)
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

-- generate a random 64-bit integer
local function random64()
   local result = 0
   local r1 = ffi.cast("uint64_t", math.random(0, 2 ^ 32 - 1))
   local r2 = ffi.cast("uint64_t", math.random(0, 2 ^ 32 - 1))

   return r1 * 4294967296ULL + r2
end

-- return a random number, preferring boundary values and
-- sometimes returning results out of range
local function choose_bounded(lo, hi, generate_invalid)
   local r = math.random()
   -- occasionally return values that are invalid for type
   -- to provoke crashes
   if generate_invalid and r < 0.05 then
      local off = math.random(1, 100)
      return choose({ lo - off, hi + off })
   elseif r < 0.15 then
      local mid = math.ceil((hi + lo) / 2)
      return choose({ lo, lo + 1, mid, mid +  1,  hi - 1, hi })
   else
      return math.random(lo, hi)
   end
end

-- Choose a random number from within a range of valid value.  RANGES
-- is an array of {LO, HI} arrays; each of LO and HI can be numbers.
-- LO can additionally be "min" and HI can be "max".
local function choose_value_from_ranges(ranges, type_min, type_max, generate_invalid)
   local r = math.random()

   if #ranges == 0 or (generate_invalid and r < 0.1) then
      return choose_bounded(type_min, type_max, generate_invalid)
   else
      local lo, hi = unpack(ranges[math.random(1,#ranges)])
      if lo == "min" then lo = type_min end
      if hi == "max" then hi = type_max end
      return choose_bounded(lo, hi, generate_invalid)
   end
end

local function value_from_type(a_type, generate_invalid)
   local prim = a_type.primitive_type
   local ranges

   if a_type.range then
      ranges = a_type.range.value
   else
      ranges = {}
   end

   if prim == "int8" then
      return choose_value_from_ranges(ranges, -128, 127, generate_invalid)
   elseif prim == "int16" then
      return choose_value_from_ranges(ranges, -32768, 32767, generate_invalid)
   elseif prim == "int32" then
      return choose_value_from_ranges(ranges, -2147483648, 2147483647, generate_invalid)
   elseif prim == "int64" then
      return ffi.cast("int64_t", random64())
   elseif prim == "uint8" then
      return choose_value_from_ranges(ranges, 0, 255, generate_invalid)
   elseif prim == "uint16" then
      return choose_value_from_ranges(ranges, 0, 65535, generate_invalid)
   elseif prim == "uint32" then
      return choose_value_from_ranges(ranges, 0, 4294967295, generate_invalid)
   elseif prim == "uint64" then
      return random64()
   -- TODO: account for fraction-digits and range
   elseif prim == "decimal64" then
      local int64 = ffi.cast("int64_t", random64())
      local exp   = math.random(1, 18)
      -- see RFC 6020 sec 9.3.1 for lexical representation
      return string.format("%f", tonumber(int64 * (10 ^ -exp)))
   elseif prim == "boolean" then
      return choose({ true, false })
   elseif prim == "ipv4-address" or prim == "ipv4-prefix" then
      local addr = {}
      for i=1,4 do
         table.insert(addr, math.random(255))
      end
      addr = table.concat(addr, ".")
      if prim == "ipv4-prefix" then
         return ("%s/%d"):format(addr, math.random(32))
      end
      return addr
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
      return value_from_type(choose(a_type.union), generate_invalid)
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

   error("NYI or unknown type: "..prim)
end

local function value_generator(typ, generate_invalid)
   -- FIXME: memoize dispatch.
   return function() return tostring(value_from_type(typ), generate_invalid) end
end

local function data_generator_from_grammar(production, generate_invalid)
   local handlers = {}
   local function visit1(keyword, production)
      return assert(handlers[production.type])(keyword, production)
   end
   local function body_generator(productions)
      local order = {}
      local gens = {}
      for k,v in pairs(productions) do
         table.insert(order, k)
         gens[k] = visit1(k, v)
         if not v.mandatory then gens[k] = maybe(gens[k]) end
      end
      table.sort(order)
      return function()
         local ret = {}
         for _,k in ipairs(order) do
            local v = gens[k]()
            if v ~= nil then table.insert(ret, v) end
         end
         return table.concat(ret, ' ')
      end
   end
   function handlers.struct(keyword, production)
      local gen = body_generator(production.members)
      local prefix, suffix = '', ''
      if keyword then prefix, suffix = keyword..' {', '}' end
      return function()
         return table.concat({prefix, gen(), suffix}, " ")
      end
   end
   function handlers.array(keyword, production)
      local gen = value_generator(production.element_type, generate_invalid)
      local prefix, suffix = '', ';'
      if keyword then prefix = keyword..' '..prefix end
      return function()
         local ret = {}
         while math.random() < 0.9 do
            table.insert(ret, prefix..gen()..suffix)
         end
         return table.concat(ret, " ")
      end
   end
   local function shallow_copy(t)
      local ret = {}
      for k,v in pairs(t) do ret[k]=v end
      return ret
   end
   function handlers.table(keyword, production)
      local keys = {}
      for k,v in pairs(production.keys) do
         keys[k] = shallow_copy(v)
         keys[k].mandatory = true
      end
      local gen_key = body_generator(production.keys)
      local gen_value = body_generator(production.values)
      local prefix, suffix = '{', '}'
      if keyword then prefix = keyword..' '..prefix end
      return function()
         local ret = {}
         while math.random() < 0.9 do
            local x = table.concat({prefix,gen_key(),gen_value(),suffix}, " ")
            table.insert(ret, x)
         end
         return table.concat(ret, " ")
      end
   end
   function handlers.scalar(keyword, production)
      local prefix, suffix = '', ''
      if keyword then
         prefix, suffix = keyword..' '..prefix, ';'
      end
      local gen = value_generator(production.argument_type, generate_invalid)
      return function()
         return prefix..gen()..suffix
      end
   end
   function handlers.choice(keyword, production)
      local choices = {}
      local cases = {}
      for case, choice in pairs(production.choices) do
         table.insert(cases, case)
         choices[case] = body_generator(choice)
      end
      table.sort(cases)
      return function ()
         return choices[choose(cases)]()
      end
   end
   return visit1(nil, production)
end
data_generator_from_grammar = util.memoize(data_generator_from_grammar)

local function path_generator_from_grammar(production, generate_invalid)
   local handlers = {}
   local function visit1(keyword, production)
      return assert(handlers[production.type])(keyword, production)
   end
   function handlers.struct(keyword, production)
      local members, gen_tail = {}, {}
      for k,v in pairs(production.members) do
         table.insert(members, k)
         gen_tail[k] = assert(visit1(k, v))
      end
      table.sort(members)
      return function ()
         local head = keyword or ''
         if #members == 0 or math.random() < 0.1 then return head end
         if head ~= '' then head = head..'/' end
         local k = choose(members)
         return head..gen_tail[k]()
      end
   end
   function handlers.array(keyword, production)
      return function ()
         local head = keyword
         if math.random() < 0.3 then return head end
         return head..'[position()='..math.random(1,100)..']'
      end
   end
   function handlers.table(keyword, production)
      local keys, values, gen_key, gen_tail = {}, {}, {}, {}
      for k,v in pairs(production.keys) do
         table.insert(keys, k)
         gen_key[k] = data_generator_from_grammar(v, generate_invalid)
      end
      for k,v in pairs(production.values) do
         table.insert(values, k)
         gen_tail[k] = visit1(k, v)
      end
      table.sort(keys)
      table.sort(values)
      return function ()
         local head = keyword
         if math.random() < 0.1 then return head end
         for _,k in ipairs(keys) do
            head = head..'['..k..'='..gen_key[k]()..']'
         end
         if math.random() < 0.1 then return head end
         return head..'/'..gen_tail[choose(values)]()
      end
   end
   function handlers.scalar(keyword, production)
      assert(keyword)
      return function() return keyword end
   end
   function handlers.choice(keyword, production)
      local choices, cases = {}, {}
      for case, choice in pairs(production.choices) do
         table.insert(cases, case)
         choices[case] = visit1(nil, {type='struct',members=choice})
      end
      table.sort(cases)
      return function() return choices[choose(cases)]() end
   end
   local gen = visit1(nil, production)
   return function() return '/'..gen() end
end
path_generator_from_grammar = util.memoize(path_generator_from_grammar)

local function choose_path_for_grammar(grammar, generate_invalid)
   return path_generator_from_grammar(grammar, generate_invalid)()
end

local function choose_path_and_value_generator_for_grammar(grammar, generate_invalid)
   local path = choose_path_for_grammar(grammar, generate_invalid)
   local getter, subgrammar = path_data.resolver(grammar, path)
   return path, data_generator_from_grammar(subgrammar, generate_invalid)
end

local function choose_path_and_value_generator(schema, is_config, generate_invalid)
   local grammar = data.data_grammar_from_schema(schema, is_config)
   return choose_path_and_value_generator_for_grammar(grammar, generate_invalid)
end

local function generate_xpath(schema, is_config, generate_invalid)
   local grammar = data.data_grammar_from_schema(schema, is_config)
   return choose_path_for_grammar(grammar, generate_invalid)
end

local function generate_xpath_and_val(schema, is_config, generate_invalid)
   local path, gen_value = choose_path_and_value_generator(
      schema, is_config, generate_invalid)
   return path, gen_value()
end

function generate_config_xpath(schema_name, generate_invalid)
   schema_name = schema_name or choose(schemas)
   local schema = schema.load_schema_by_name(schema_name)
   return generate_xpath(schema, true, generate_invalid), schema_name
end

-- types that may be randomly picked for a fuzzed test case
local types = { "int8", "int16", "int32", "int64", "uint8", "uint16",
                "uint32", "uint64", "decimal64", "boolean", "ipv4-address",
                "ipv6-address", "ipv6-prefix", "mac-address", "string",
                "binary" }

function generate_config_xpath_and_val(schema_name, generate_invalid)
   schema_name = schema_name or choose(schemas)
   local schema = schema.load_schema_by_name(schema_name)
   local r = math.random()
   local path, val

   -- once in a while, generate a nonsense value
   if generate_invalid and r < 0.05 then
     path = generate_xpath(schema, true)
     val = value_from_type({ primitive_type=choose(types) }, generate_invalid)
   else
     path, val = generate_xpath_and_val(schema, true, generate_invalid)
   end

   return path, val, schema_name
end

function generate_state_xpath(schema_name, generate_invalid)
   schema_name = schema_name or choose(schemas)
   local schema = schema.load_schema_by_name(schema_name)
   return generate_xpath(schema, false, generate_invalid), schema_name
end

function selftest()
   print('selftest: program.lwaftr.tests.propbased.genyang')
   local schema = schema.load_schema_by_name("snabb-softwire-v3")
   local grammar = data.config_grammar_from_schema(schema)

   for i=1,1000 do generate_xpath_and_val(schema, true) end
   for i=1,1000 do generate_xpath_and_val(schema, false) end

   -- check some int types with range statements
   for i=1, 100 do
      local val1 = value_from_type({ primitive_type="uint8",
                                     range={ value = {{1, 16}} } })
      local val2 = value_from_type({ primitive_type="uint8",
                                     range={ value = {{1, 16}, {18, 32}} } })
      local val3 = value_from_type({ primitive_type="uint8",
                                     range={ value = {{"min", 10}, {250, "max"}} } })
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
   print('selftest: ok')
end
