-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local schema = require("lib.yang.schema")
local data = require("lib.yang.data")

load_schema = schema.load_schema
load_schema_file = schema.load_schema_file
load_schema_by_name = schema.load_schema_by_name

load_data_for_schema = data.load_data_for_schema
load_data_for_schema_by_name = data.load_data_for_schema_by_name

function selftest()
end
