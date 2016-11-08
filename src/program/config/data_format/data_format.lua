-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local lib = require("core.lib")
local schema = require("lib.yang.schema")
local yang_data = require("lib.yang.data")

-- Number of spaces a tab should consist of when indenting config.
local tab_spaces = 2

local function print_level(level, ...)
   io.write(string.rep(" ", level * tab_spaces))
   print(...)
end

local function union_type(union)
   local rtn
   for _, t in pairs(union.argument_type.union) do
      if rtn then
	 rtn = rtn .. " | " .. t.argument_string
      else
	 rtn = t.argument_string
      end
   end
   return rtn
end

local function comment(opts)
   local comments = {}
   if opts.mandatory == true then
      comments[#comments + 1] = "mandatory"
   end
   if opts.key then
      comments[#comments + 1] = "key"
   end
   if opts.range then
      comments[#comments + 1] = "between " .. opts.range
   end
   local rtn = nil
   for n, c in pairs(comments) do
      if n == 1 then
	 rtn = "// " .. c
      else
	 rtn = rtn  .. " " .. c
      end
   end
   return rtn
end

local function display_leaf(level, keyword, argument, opts)
   if argument == "union" then argument = union_type(node) end
   local comments
   if opts then comments = comment(opts) end
   local str = keyword .. " ".. argument .. ";"
   if comments then
      print_level(level, str .. " " .. comments)
   else
      print_level(level, str)
   end
end

local function show_usage(status)
   print(require("program.config.data_format.README_inc"))
   main.exit(status)
end

-- Contains verious option handling code.
local options = {}

function options.key(keys)
   return function (name)
      for _, k in pairs(keys) do
	 if name == k then return true end
      end
      return false
   end
end

function options.range(name, node)
   if node.argument_type.range then
      return node.argument_type.range.argument_string
   end
   return nil
end

-- Contains the handlers which know how to describe certain data node types.
local describers = {}

local function describe(level, name, node, ...)
   local err = "Unknown node type: "..node.type
   assert(describers[node.type], err)(level, name, node, ...)
end

local function describe_members(node, level, ...)
   if level == nil then level = 0 end
   for name, n in pairs(node.members) do
      describe(level, name, n, ...)
   end
end

function describers.scalar(level, name, node, is_key)
   local opts = {}
   if is_key then opts.key = is_key(name, node) end
   opts.mandatory = node.mandatory
   opts.range = options.range(name, node)
   display_leaf(level, name, node.argument_type.argument_string, opts)
end

function describers.table(level, name, node)
   print_level(level, "// List, key(s) must be unique.")
   print_level(level, name.." {")
   describe_members(node, level + 1, options.key(node.keys))
   print_level(level, "}")
end

function describers.struct(level, name, node)
   print_level(level, name.." {")
   describe_members(node, level + 1)
   print_level(level, "}")
end

function describers.array(level, name, node)
   print_level(level, "// Array, multiple elements by repeating the statement.")
   display_leaf(level, name, node.element_type.argument_string)
end

local function parse_args(args)
   local handlers = {}
   handlers.h = function() show_usage(0) end
   args = lib.dogetopt(args, handlers, "h", {help="h"})
   if #args ~= 0 then show_usage(1) end
   return unpack(args)
end

function run(args)
   local yang_module = parse_args(args)

   -- Fetch and parse the schema module.
   local s = schema.parse_schema_file(yang_module)
   local grammar = yang_data.data_grammar_from_schema(s)

   describe_members(grammar)
end
