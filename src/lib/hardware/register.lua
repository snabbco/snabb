-- register.lua -- Hardware device register abstraction

module(...,package.seeall)

local lib = require("core.lib")

--- ### Register object
--- There are three types of register objects, set by the mode when created:
--- * `RO` - read only.
--- * `RW` - read-write.
--- * `RC` - read-only and return the sum of all values read. This
---   mode is for counter registers that clear back to zero when read.

Register = {}

--- Read a standard register
function Register:read ()
   return self.ptr[0]
end

--- Read a counter register
function Register:readrc ()
   -- XXX JIT of this function is causing register value to be misread.
   jit.off(true,true)
   local value = self.ptr[0]
   self.acc = (self.acc or 0) + value
   return self.acc
end

--- Write a register
function Register:write (value)
   self.ptr[0] = value
   return value
end

--- Set and clear specific masked bits.
function Register:set (bitmask) self(bit.bor(self(), bitmask)) end
function Register:clr (bitmask) self(bit.band(self(), bit.bnot(bitmask))) end

--- Block until applying `bitmask` to the register value gives `value`.
--- If `value` is not given then until all bits in the mask are set.
function Register:wait (bitmask, value)
   lib.waitfor(function ()
		  return bit.band(self(), bitmask) == (value or bitmask)
	       end)
end

--- For type `RC`: Reset the accumulator to 0.
function Register:reset () self.acc = 0 end

--- For other registers provide a noop
function Register:noop () end

--- Register objects are "callable" as functions for convenience:
---     reg()      <=> reg:read()
---     reg(value) <=> reg:write(value)
function Register:__call (value)
   if value then return self:write(value) else return self:read() end
end

--- Registers print as `$NAME:$HEXVALUE` to make debugging easy.
function Register:__tostring ()
   return self.name..":"..bit.tohex(self())
end

--- Metatables for the three different types of register
local mt = {
  RO = {__index = { read=Register.read, wait=Register.wait, reset=Register.noop},
        __call = Register.read, __tostring = Register.__tostring},
  RW = {__index = { read=Register.read, write=Register.write, wait=Register.wait,
                    set=Register.set, clr=Register.clr, reset=Register.noop},
        __call = Register.__call, __tostring = Register.__tostring},
  RC = {__index = { read=Register.readrc, reset=Register.reset},
        __call = Register.readrc, __tostring = Register.__tostring},
}

--- Create a register `offset` bytes from `base_ptr`.
---
--- Example:
---     register.new("TPT", "Total Packets Transmitted", 0x040D4, ptr, "RC")
function new (name, longname, offset, base_ptr, mode)
   local o = { name=name, longname=longname,
	       ptr=base_ptr + offset/4 }
   local mt = mt[mode]
   assert(mt)
   return setmetatable(o, mt)
end

--- ### Define registers from string description.

--- Define a set of registers described by a string.
--- The register objects become named entries in `table`.
---
--- This is an example line for a register description:
---     TXDCTL    0x06028 +0x40*0..127 (RW) Transmit Descriptor Control
---
--- and this is the grammar:
---     Register   ::= Name Offset Indexing Mode Longname
---     Name       ::= <identifier>
---     Indexing   ::= "-"
---                ::= "+" OffsetStep "*" Min ".." Max
---     Mode       ::= "RO" | "RW" | "RC"
---     Longname   ::= <string>
---     Offset ::= OffsetStep ::= Min ::= Max ::= <number>
function define (description, table, base_ptr)
   local pattern = [[ *(%S+) +(%S+) +(%S+) +(%S+) (.-)
]]
   for name,offset,index,perm,longname in description:gmatch(pattern) do
      table[name] = new(name, longname, tonumber(offset), base_ptr, perm)
   end
end

-- Print a pretty-printed register dump for a table of register objects.
function dump (tab, iscounters)
   print "Register dump:"
   local strings = {}
   for _,reg in pairs(tab) do
      if iscounters == nil or reg() > 0 then
         table.insert(strings, reg)
      end
   end
   table.sort(strings, function(a,b) return a.name < b.name end)
   for _,reg in pairs(strings) do
      if iscounters then
         io.write(("%20s %16s %s\n"):format(reg.name, lib.comma_value(reg()), reg.longname))
      else
         io.write(("%20s %s\n"):format(reg, reg.longname))
      end
   end
end
