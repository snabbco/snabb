module(..., package.seeall)

local pf = require("pf")

local filter = subClass(nil)
filter._name = "pcap packet filter"

-- Create a filter with an arbitrary libpcap filter expression
function filter:new(program)
   local o = filter:superClass().new(self)
   o._filter = pf.compile_filter(program, {})
   return o
end

-- Apply the filter to a region of memory
function filter:match(data, length)
   return self._filter(data, length)
end

return filter
