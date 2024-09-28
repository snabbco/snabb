module(..., package.seeall)

local schema     = require("lib.yang.schema")
local yang       = require('lib.yang.yang')

function run (parameters)
   local schema_name = 'test-schema-v1'
   local schema = schema.load_schema_by_name(schema_name)
   local conf = yang.load_configuration(parameters[1],{schema_name=schema_name, verbose = true})

   local c = config.new()
   engine.configure(c)
   engine.main({duration=1})
end
