-- This module implements utility functions, e.g. debug prints, for
-- the flow export app

module(..., package.seeall)

-- intended for use in blocks like `if debug ... end`
function fe_debug(...)
   print(string.format("%s | %s", os.date("%F %H:%M:%S"), string.format(...)))
end
