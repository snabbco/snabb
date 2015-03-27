-- This class provides basic mechanisms for parsing, building and
-- manipulating a hierarchy of protocol headers and associated payload
-- contained in a data packet.  In particular, it supports
--
--   Parsing and in-place manipulation of protocol headers in a
--   received packet
--
--   In-place decapsulation by removing leading protocol headers
--
--   Adding headers to an existing packet
--
--   Creation of a new packet
--
-- It keeps track of a "parse stack" consisting of an (indexed) stack of
-- header objects and an offset into the packet.
--
-- When a new datagram is created, the parse stack index and the offset
-- are both initialized to zero, such that parsing starts at the
-- beginning of the packet and the entire packet is considered as
-- payload.
--
-- When one of the parser methods is called, the offset is advanced by
-- the size of the parsed header (and the payload reduced
-- correspondingly).
--
-- Also note that parsing does not change the packet itself.  However,
-- the header at the bottom of the parse stack (which is located at the
-- beginning of the buffer's valid data) can be removed from the packet
-- by calling the pop() method, which truncates the underlying packet
-- accordingly.
--
-- The push() method can be used to prepend headers in front of the
-- packet.
--
-- IMPORTANT: Both pop() and push() destructively modify the packet and
-- headers previously obtained by calls to parse_*() will be corrupted.
--
-- To construct a packet from scratch, the constructor is called without
-- a reference to a packet.  In this case, a new empty packet is
-- allocated.  All methods are applicable to such a datagram.

module(..., package.seeall)
local packet = require("core.packet")
local ffi    = require("ffi")

local datagram = subClass(nil)

-- Class methods

-- Create a datagram from a packet or from scratch (if p == nil).  The
-- class argument is only relevant for parsing and can be set to the
-- header class of the the outermost packet header.  
local function init (o, p, class)
   if not o._recycled then
      o._parse = { stack = {}, index = 0 }
      o._packet = ffi.new("struct packet *[1]")
   elseif o._parse.stack[1] then
      for i, _ in ipairs(o._parse.stack) do
	 o._parse.stack[i]:free()
	 o._parse.stack[i] = nil
      end
      o._parse.index = 0
   end
   o._parse.offset = 0
   o._parse.ulp = class
   o._packet[0] = p or packet.allocate()
   return o
end

function datagram:new (p, class)
   return(init(datagram:superClass().new(self), p, class))
end

-- Reuse an existing object to avoid putting it on the freelist.
-- Caution: This will free the datagram's current packet.
function datagram:reuse (p, class)
   self._recycled = true
   return(init(self, p, class))
end

-- Instance methods

-- Push a new protocol header to the front of the packet.
function datagram:push (proto)
   packet.prepend(self._packet[0], proto:header(), proto:sizeof())
   self._parse.offset = self._parse.offset + proto:sizeof()
end

-- The following methods create protocol header objects from the
-- packet's payload.  The basic method parse_match() takes two
-- arguments, which can both be nil.
--
-- The first argument is a protocol class object which is used to
-- create a protocol instance from the start of the as yet unparsed
-- part of the packet.  If class is nil, the current ULP of the packet
-- is used.  If the ULP is not set (nil) or the constructor of the
-- protocol instance returns nil, the parsing operation has failed and
-- the method returns nil.  The packet remains unchanged.
--
-- If the protocol instance has been created successfully, it is
-- passed as single argument to the anonymous function that has been
-- passed as the second argument to the method.  The function can
-- execute any checks that should be performed on the protocol, like
-- matching of a particular value of a header field.  It must return
-- either true or false.
--
-- If the checking function returns false, the parsing has failed and
-- the method returns nil.  The packet remains unchanged.
--
-- If no checking function is supplied or it returns a true value, the
-- parsing has succeeded.  The protocol object is pushed onto the
-- datagrams parse stack and returned to the caller.
function datagram:parse_match (class, check)
   local parse = self._parse
   local class = class or parse.ulp
   if not class then return nil end
   local proto = class:new_from_mem(packet.data(self._packet[0]) + parse.offset,
                                    packet.length(self._packet[0]) - parse.offset)
   if proto == nil or (check and not check(proto)) then
      if proto then proto:free() end
      return nil
   end
   local index = parse.index + 1
   parse.stack[index] = proto
   parse.index = index
   parse.ulp = proto:upper_layer()
   parse.offset = parse.offset + proto:sizeof()
   return proto
end

-- This method is a wrapper for parse_match() that allows parsing of a
-- sequence of headers with a single method call.  The method returns
-- the protocol object of the final parsed header or nil if any of the
-- calls to parse_match() return nil.  If called with a nil argument,
-- this method is equivalent to parse_match() without arguments.
function datagram:parse (seq)
   if not seq then
      return self:parse_match()
   end
   local proto = nil
   local i = 1
   while seq[i] do
      proto = self:parse_match(seq[i][1], seq[i][2])
      if not proto then break end
      i = i+1
   end
   return proto
end

-- This method is a wrapper for parse_match() that parses the next n
-- protocol headers.  It returns the last protocol object or nil if
-- less than n headers could be parsed successfully.
function datagram:parse_n (n)
   local n = n or 1
   local proto
   for i = 1, n do
      proto = self:parse_match()
      if not proto then break end
   end
   return proto
end

-- Undo the last n calls to parse, returning the associated headers to
-- the packet's payload.
function datagram:unparse (n)
   local parse = self._parse
   local proto
   while n > 0 and parse.index ~= 0 do
      -- Don't use table.remove to avoid garbage
      proto = parse.stack[parse.index]
      parse.index = parse.index - 1
      proto:free()
      parse.offset = parse.offset - proto:sizeof()
      parse.ulp = proto:class()
      n = n - 1
   end
end

-- Remove the bytes of the bottom <n> headers from the parse stack from
-- the start of the packet.
function datagram:pop (n)
   local parse = self._parse
   local n_bytes = 0
   assert(n <= parse.index)
   for i = 1, parse.index do
      if i <= n then
	 local proto = parse.stack[i]
         n_bytes = n_bytes + proto:sizeof()
	 proto:free()
      end
      if i+n <= parse.index then
	 parse.stack[i] = parse.stack[i+n]
      else
	 parse.stack[i] = nil
      end
   end
   parse.index = parse.index - n
   self:pop_raw(n_bytes)
   self._parse.offset = self._parse.offset - n_bytes
end

-- Remove <length> bytes from the start of the packet and set upper-layer
-- protocol to <ulp> if <ulp> is supplied.
function datagram:pop_raw (length, ulp)
   packet.shiftleft(self._packet[0], length)
   if ulp then self._parse.ulp = ulp end
end

function datagram:stack ()
   return(self._parse.stack)
end

function datagram:packet ()
   return(self._packet[0])
end

-- Return the location and size of the packet's payload.  If mem is
-- non-nil, the memory region at the given address and size is
-- appended to the packet's payload first.
function datagram:payload (mem, size)
   if mem then packet.append(self._packet[0], mem, size) end
   return packet.data(self._packet[0]) + self._parse.offset,
          packet.length(self._packet[0]) - self._parse.offset
end

return datagram
