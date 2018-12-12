-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Base class for a particular ICMP type.  It provides specialization
-- for codes within the type that use specific data formats (this
-- can't be done with the _class_map mechanism because the ICMP code
-- is part of the ICMP header).  To make use of this, derived classes
-- must supply a class variable called _code_map, which must be a
-- table holding ctypes indexed by the code value.

module(..., package.seeall)

local ffi = require("ffi")
local proto_header = require("lib.protocol.header")

local du = subClass(proto_header)

function du:specialize (code)
   assert(self._code_map)
   local header_idx = assert(self._code_map[code])
   local header_ptr = self._header.box[0]
   self._header = assert(self._headers[header_idx])
   self._header.box[0] = ffi.cast(self._header.ptr_t,
                                  header_ptr)
   return self
end

return du
