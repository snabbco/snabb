-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local schema = require("lib.yang.schema")
local data = require("lib.yang.data")
local binary = require("lib.yang.binary")

load_schema = schema.load_schema
load_schema_file = schema.load_schema_file
load_schema_by_name = schema.load_schema_by_name

load_data_for_schema = data.load_data_for_schema
load_data_for_schema_by_name = data.load_data_for_schema_by_name

compile_data_for_schema = binary.compile_data_for_schema
compile_data_for_schema_by_name = binary.compile_data_for_schema_by_name

load_compiled_data_file = binary.load_compiled_data_file

function selftest()
end
