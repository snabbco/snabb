module(..., package.seeall)

local ffi = require("ffi")

-- A canary is a small piece of memory with a well-known expected content.
--
-- You can place canaries in memory locations where you are especially
-- worried about heap corruption. Then you can regularly check() to
-- see if any canary's expected contents has been overwritten by
-- something else. This gives you the chance to quickly detect which
-- specific memory area has been corrupted.
--
-- "Canary in a coal mine": http://en.wiktionary.org/wiki/canary_in_a_coal_mine

require("canary_h")
local ffi = require("ffi")

size = ffi.C.CANARY_SIZE

canaries = {} -- index->canary
names    = {} -- index->name

-- Register a named canary for checking.
function register (name, canary)
   for i = 0, size-1 do
      canary.bytes[i] = i
   end
   table.insert(canaries, canary)
   table.insert(names, name)
   return canary
end

-- Check all registered canaries and print postmortem analysis for dead ones.
function check ()
   local fail = false
   for i,c in pairs(canaries) do
      if is_dead(c) then
	 fail = true
	 print("canary '" .. names[i] .. "' died. Stomach contents:")
	 hexdump(c)
	 print()
      end
   end
   assert(not fail, "dead canary")
end

function is_dead (c)
   for i = 0, size-1 do
      if c.bytes[i] ~= i % 256 then return true end
   end
end

function hexdump (c)
   for i = 0, size-1 do
      if i % 16 == 0 then
	 -- print line address
	 if i > 0 then print() end
	 io.write(bit.tohex(i).."  ")
      end
      io.write(bit.tohex(c.bytes[i],2))
      if c.bytes[i] ~= i % 256 then io.write("?") else io.write(" ") end
   end
end

function selftest ()
   local test = ffi.new("struct { struct canary c1, c2; }")
   register("canary #1", test.c1)
   register("canary #2", test.c2)
   print("Checking with live canaries..")
   check()
   test.c1.bytes[0] = 0xff
   test.c2.bytes[1] = 0xff
   print("Checking with dead canaries..")
   check()
end

