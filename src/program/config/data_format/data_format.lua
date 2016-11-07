-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local lib = require("core.lib")
local schema = require("lib.yang.schema")
local yang_data = require("lib.yang.data")
local usage = require("program.config.data_format.README_inc")

-- Number of spaces a tab should consist of when indenting config.
local tab_spaces = 4

local function show_usage(status)
   print(require("program.config.data_format.README_inc"))
   main.exit(status)
end

local function parse_args(args)
   local handlers = {}
   handlers.h = function() show_usage(0) end
   args = lib.dogetopt(args, handlers, "h", {help="h"})
   if #args <= 0 then show_usage(1) end
   return unpack(args)
end

function run(args)
   function print_level(level, ...)
      io.write(string.rep(" ", level * tab_spaces))
      print(...)
   end
   function union_type(union)
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
   function collate_options(name, node, keys)
      local options = {}
      if keys ~= nil then
	 for _, k in pairs(keys) do
	    if name == k then options.key = true end
	 end
      end
      if node.argument_type then
	 local at = node.argument_type
	 if at.range then
	    options.range = at.range.argument_string
	 end
      end
      if node.mandatory then
	 options.mandatory = true
      end
      return options
   end
   function display_node(name, node, options, level, parent)
      function comment()
	 local comments = {}
	 if options.mandatory == true then
	    comments[#comments + 1] = "mandatory"
	 end
	 if options.key then
	    comments[#comments + 1] = "key"
	 end
	 if options.range then
	    comments[#comments + 1] = "between " .. options.range
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
      function display_leaf(keyword, argument)
	 if argument == "union" then argument = union_type(node) end
	 local comments = comment()
	 local str = keyword .. " " .. argument .. ";"
	 if comments then
	    print_level(level, str .. " " .. comments)
	 else
	    print_level(level, str)
	 end
      end
      if level == nil then level = 0 end
      if node.type == "table" or node.type == "struct" then
	 local keys = {}
	 if node.keys then
	    print_level(
	       level,
	       "// List: this nested structure is repeated with (a) unique key(s)"
	    )
	 end
	 print_level(level, name.." {")
         display_data_format(node, level + 1)
         print_level(level, "}")
      elseif node.type == "scalar" then
         display_leaf(name, node.argument_type.argument_string)
      elseif node.type == "array" then
	 print_level(
	    level,
	    "// Array: made by repeating the keyword followed by each element"
	 )
	 display_leaf(name, node.element_type.argument_string)
      else
      end
   end

   function display_data_format(grammar, level)
      for k,v in pairs(grammar.members) do
	 local options = collate_options(k, v, grammar.keys)
         display_node(k, v, options, level)
      end
   end


   local yang_module = parse_args(args)

   -- Fetch and parse the schema module.
   local s = schema.parse_schema_file(yang_module)
   local grammar = yang_data.data_grammar_from_schema(s)

   display_data_format(grammar, 0)
end
