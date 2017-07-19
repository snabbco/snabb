-- This module implements utility functions, e.g. debug prints, for
-- the flow export app

module(..., package.seeall)

ffi = require("ffi")

local C = ffi.C

-- intended for use in blocks like `if debug ... end`
function fe_debug(...)
   print(string.format("%s | %s", os.date("%F %H:%M:%S"), string.format(...)))
end

-- produce a timestamp in milliseconds
function get_timestamp()
   return C.get_unix_time() * 1000ULL
end
