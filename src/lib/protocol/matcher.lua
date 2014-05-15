-- This module provides a minimalistic but efficient framework to
-- check whether a chunk of memory contains specific byte-strings of a
-- certain size at particular offsets.  It is used to perform
-- rudimentary classification of data packets.
--
-- This is a hack and should be replaced by something less clunky and
-- more versatile, e.g. the matching engine of libpcap.
--
-- To avoid garbage, it is written in C with a minimal Lua wrapper.
-- The number of matcher objects is fixed by the parameter
-- MAX_MATCHERS in lib/matcher.h.
-- 
-- When a matcher object is instantiated, it grabs the next free
-- matcher from the global list.  The index into this list is stored
-- as a handle in the object.
--
-- The application can add up to MAX_RULES (lib/matcher.h) matching
-- rules given as the three-tuple offset, size, data by calling the
-- matcher:add_rule() method.
--
-- The actual matching is performed by calling the compare() method on
-- a chunk of memory given by its base address and size.
--

module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
require("lib.protocol.matcher_h")
local matcher = subClass(nil)
matcher._name = "matcher"

local max_rules = 16


function matcher:new()
   local o = matcher:superClass().new(self)
   local id = C.matcher_new()
   assert(id >= 0, "could not create matcher")
   o._id = id
   o._data = {}
   return o
end

function matcher:add(offset, size, data)
   assert(C.matcher_add_rule(self._id, offset, size, data))
   -- Keep a reference to data to keep it from getting garbage collected
   table.insert(self._data, data)
end

-- The result of this method is true if all rules match, false otherwise
function matcher:compare(mem, size)
   return C.matcher_compare(self._id, mem, size)
end

return matcher
