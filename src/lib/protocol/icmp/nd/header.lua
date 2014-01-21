require("class")
local ffi = require("ffi")
local proto_header = require("lib.protocol.header")
local tlv = require("lib.protocol.icmp.nd.options.tlv")

local nd_header = subClass(proto_header)

function nd_header:options(mem, size)
   local result = {}
   while size > 0 do
      local tlv = tlv:new_from_mem(mem, size)
      table.insert(result, tlv)
      local tlv_size = tlv:length()*8
      mem = mem + tlv_size
      size = size - tlv_size
   end
   assert(size == 0, "corrupt ND options")
   return(result)
end

return nd_header
