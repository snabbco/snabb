-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- register.lua -- Hardware device register abstraction

module(...,package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local band = bit.band

--- ### Register object
--- There are eight types of register objects, set by the mode when created:
--- * `RO` - read only.
--- * `RW` - read-write.
--- * `RC` - read-only and return the sum of all values read.
---   mode is for counter registers that clear back to zero when read.
--- * `RCR` - read-only counter for registers that don't reset on read
--- Each has a corresponding 64bit version, `RO64`, `RW64`, `RC64`, `RCR64`

Register = {}

--- Read a standard register
function Register:read ()
   return self.ptr[0]
end

--- Read a counter register
function Register:readrc ()
   self.acc[0] = self.acc[0] + self.ptr[0]
   return self.acc[0]
end

function Register:readrcr ()
   local val =  self.ptr[0]
   self.acc[0] = self.acc[0] + bit.band(val - self.prev[0], 0xFFFFFFFF)
   self.prev[0] = val
  return self.acc[0]
end

--- Write a register
function Register:write (value)
   self.ptr[0] = value
   return value
end

--- Set and clear specific masked bits.
function Register:set (bitmask) self(bit.bor(self(), bitmask)) end
function Register:clr (bitmask) self(bit.band(self(), bit.bnot(bitmask))) end

function ro_bits (register, start, length)
    return bit.band(bit.rshift(register(), start), 2^length - 1)
end

-- Get / set length bits of the register at offset start
-- if bits == nil then return length bits from the register at offset start
-- if bits ~= nil then set length bits in the register at offset start
function Register:bits (start, length, bits)
  if bits == nil then
    return ro_bits(self, start, length)
  else
    local tmp = self()
    local offmask = bit.bnot(bit.lshift(2^length - 1, start))
    tmp = bit.band(tmp, offmask)
    tmp = bit.bor(tmp, bit.lshift(bits, start))
    self(tmp)
  end
end
function ro_byte (register, start, byte)
  return register:bits(start * 8, 8)
end
-- Get / set a byte length bytes from an offset of start bytes
function Register:byte (start, byte)
  if byte == nil then
    return ro_byte(self, start, byte)
  else
    self:bits(start * 8, 8, byte)
  end
end

--- Block until applying `bitmask` to the register value gives `value`.
--- If `value` is not given then until all bits in the mask are set.
function Register:wait (bitmask, value)
   lib.waitfor(function ()
      return bit.band(self(), bitmask) == (value or bitmask)
   end)
end

--- For type `RC`: Reset the accumulator to 0.
function Register:reset () self.acc[0] = 0ULL end

--- For other registers provide a noop
function Register:noop () end

--- Print a standard register
function Register:print ()
   io.write(("%40s %s\n"):format(self, self.longname))
end

--- Print a counter register unless its accumulator value is 0.
function Register:printrc ()
   if self() > 0 then
      io.write(("%40s (%16s) %s\n"):format(self, lib.comma_value(self()), self.longname))
   end
end

--- Register objects are "callable" as functions for convenience:
---     reg()      <=> reg:read()
---     reg(value) <=> reg:write(value)
function Register:__call (value)
   if value then return (self:write(value)) else return (self:read()) end
end

--- Registers print as `$NAME:$HEXVALUE` to make debugging easy.
function Register:__tostring ()
   return self.name.."["..bit.tohex(self.offset).."]:"..bit.tohex(self())
end

--- Metatables for the three different types of register
local mt = {
  RO = {__index = { read=Register.read, wait=Register.wait,
                    reset=Register.noop, print=Register.print,
                    bits=ro_bits, byte=ro_byte},
        __call = Register.read, __tostring = Register.__tostring},
  RW = {__index = { read=Register.read, write=Register.write, wait=Register.wait,
                    set=Register.set, clr=Register.clr, reset=Register.noop,
                    bits=Register.bits, byte=Register.byte, print=Register.print},
        __call = Register.__call, __tostring = Register.__tostring},
  RC = {__index = { read=Register.readrc, reset=Register.reset,
                    bits=ro_bits, byte=ro_byte,
                    print=Register.printrc},
        __call = Register.readrc, __tostring = Register.__tostring},
  RCR = { __index = { read=Register.readrcr, reset = Register.reset,
                    bits=ro_bits, byte=ro_byte,
                    print=Register.printrc},
          __call = Register.readrcr, __tostring = Register.__tostring  }
}
mt['RO64'] = mt.RO
mt['RW64'] = mt.RW
mt['RC64'] = mt.RC
mt['RCR64'] = mt.RCR

--- Create a register `offset` bytes from `base_ptr`.
---
--- Example:
---     register.new("TPT", "Total Packets Transmitted", 0x040D4, ptr, "RC")
function new (name, longname, offset, base_ptr, mode)
   local o = { name=name, longname=longname, offset=offset,
               ptr=base_ptr + offset/4 }
   local mt = mt[mode]
   assert(mt)
   if string.find(mode, "^RC") then
      o.acc = ffi.new("uint64_t[1]")
   end
   if string.find(mode, "64$") then
      o.ptr = ffi.cast("uint64_t*", o.ptr)
   end
   if string.find(mode, "^RCR") then
      o.prev = ffi.new("uint64_t[1]")
   end
   return setmetatable(o, mt)
end

--- returns true if an index string represents a range of registers
function is_range (index)
   return index:match('^%+[%xx]+%*%d+%.%.%d+$') ~= nil
end

--- iterates the offset as defined in a range of registers
function iter_range (offset, index)
   local step,s,e =  string.match(index, '+([%xx]+)%*(%d+)%.%.(%d+)')
   step, s, e = tonumber(step), tonumber(s), tonumber(e)
   local function iter(e, i)
      i = i + 1
      if i > e then return nil end
      return i, offset+step*(i-s)
   end
   return iter, e, s-1
end

--- returns the n-th offset in a register range
function in_range (offset, index, n)
   offset = tonumber(offset)
   if offset == nil then return nil end
   n = tonumber(n) or 0
   local step,s,e =  string.match(index, '+([%xx]+)%*(%d+)%.%.(%d+)')
   if not step then return offset end
   step, s, e = tonumber(step), tonumber(s), tonumber(e)
   if s <= n and n <= e then
      return offset + step * (n-s)
   end
   return nil
end

--- formats a name for a specific member of a register range
function range_name (index, name, i)
   local step,s,e =  string.match(index, '+([%xx]+)%*(%d+)%.%.(%d+)')
   local ndigits = #(tostring(tonumber(e)))
   local fmt = string.format('%%s[%%0%dd]', ndigits)
   return string.format(fmt, name, i)
end

--- ### Define registers from string description.

--- Define a set of registers described by a string.
--- The register objects become named entries in `table`.
---
--- This is an example line for a register description:
---     TXDCTL    0x06028 +0x40*0..127 RW Transmit Descriptor Control
---
--- and this is the grammar:
---     Register   ::= Name Offset Indexing Mode Longname
---     Name       ::= <identifier>
---     Indexing   ::= "-"
---                ::= "+" OffsetStep "*" Min ".." Max
---     Mode       ::= "RO" | "RW" | "RC" | "RCR" | "RO64" | "RW64" | "RC64" | "RCR64"
---     Longname   ::= <string>
---     Offset ::= OffsetStep ::= Min ::= Max ::= <number>
---
--- the optional 'n' argument specifies which register of an array gets
--- created (default 0)
function define (description, table, base_ptr, n)
   local pattern = [[ *(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(.-)
]]
   for name,offset,index,perm,longname in description:gmatch(pattern) do
      local offs = in_range(offset, index, n)
      if offs ~= nil then
         table[name] = new(name, longname, offs, base_ptr, perm)
      end
   end
end

-- registers of the form '+0xXX*j..k' are converted to
-- an array of registers.
-- naïve implementation: actually create the whole array
function define_array (description, table, base_ptr)
   local pattern = [[ *(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(.-)
]]
   for name,offset,index,perm,longname in description:gmatch(pattern) do
      if is_range(index) then
         table[name] = table[name] or {name=name}
         for i, offset in iter_range(offset, index) do
            table[name][i] = new(range_name(index,name,i), longname, offset, base_ptr, perm)
         end
      else
         table[name] = new(name, longname, offset, base_ptr, perm)
      end
   end
end


function is_array (t)
   return type(t)=='table' and getmetatable(t)==nil
end


-- Print a pretty-printed register dump for a table of register objects.
function dump (tab)
--   print "Register dump:"
   local strings = {}
   for _,reg in pairs(tab) do
      if type(reg)=='table' then
         table.insert(strings, reg)
      end
   end
   table.sort(strings, function(a,b) return a.name < b.name end)
   for _,reg in ipairs(strings) do
      if is_array(reg) then
         dump(reg)
      else
         reg:print()
      end
   end
end
