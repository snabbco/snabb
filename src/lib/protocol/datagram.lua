-- This class provides basic mechanisms for parsing, building and
-- manipulating a hierarchy of protocol headers and associated payload
-- contained in a data packet.  In particular, it supports
--
--   Parsing and in-place manipulation of protocol headers in a
--   received packet
--
--   In-place decapsulation by removing leading protocol headers
--
--   Adding encapsulation headers to an existing packet
--
--   Creation of a new packet
--
-- This functionality is provided by keeping track of two separate
-- header stacks, called the "parse stack" and the "push stack".  The
-- parse stack is built from the data contained in an existing packet
-- while the push stack is built from newly created protocol headers.
-- For the parse stack, the protocol object's data is the actual
-- memory region in the packet buffer, where as the push() method
-- merely creates a copy of the header in the packet buffer.
-- Therefore, all manipulations performed with the protocol object
-- must be completed before the header is push()-ed onto the packet.
--
-- The parse stack uses the notion of an "upper-layer protocol" (ULP)
-- to identify which protocol class to use to parse the next chunk of
-- data in the packet payload.  The ULP is determined by calling the
-- upper_layer() method of the topmost protocol on the parse stack.
--
-- When a datagram is created from an existing packet, the packet's
-- buffers are first coalesced into a single buffer to make the entire
-- packet accessible in a contigous region of memory and an empty
-- parse stack is created with an initial user-defined ULP.  At any
-- point in time, the portion of the packet that is not yet parsed is
-- considered to be the current payload of the packet.
--
-- When a datagram is created from scratch, an empty packet
-- (containing no buffers) is allocated.  The only valid method for
-- such a datagram is push(), which, when called for the first time,
-- allocates a new buffer to store the push stack's header in.
-- Another new buffer is allocated for the packet's payload.  The
-- parse() method is not applicable to such a datagram.

module(..., package.seeall)
local packet = require("core.packet")
local buffer = require("core.buffer")
local ffi    = require("ffi")

local datagram = subClass(nil)

-- Class methods

-- When the constructor is called with an existing packet, the
-- packet's buffers are coalesced into one and the parse stack is
-- initialized for it.  If p == nil, a new empty packet is allocated.
-- The allocation of buffers is delayed until the first call of the
-- push() method.
function datagram:new (p, class)
   local o = datagram:superClass().new(self)
   if p then
      packet.coalesce(p)
      o._packet = p
   else
      o._packet = packet.allocate()
      local b = buffer.allocate()
      packet.add_iovec(o._packet, b, 0)
   end
   if not o._recycled then
      o._parse = { stack = {}, index = 0 }
   else
      for i, _ in ipairs(o._parse.stack) do
	 o._parse.stack[i]:free()
	 o._parse.stack[i] = nil
      end
      o._parse.index = 0
      o._push = nil
   end
   o._parse.ulp = class
   o._parse.iovec = 0
   o._parse.offset = 0
   return o
end

-- Instance methods

-- Add a new protocol header to the push stack, creating the stack
-- first if it doesn't exist.  If there is no parse stack either,
-- we're dealing with a datagram that has been created from scratch.
-- In this case, we add another empty buffer and set the ULP to nil,
-- which makes this packet effectively non-parseable, but it can still
-- hold the packet's payload.
function datagram:push (proto)
   local push = self._push
   if not push then
      local b = buffer.allocate()
      packet.prepend_iovec(self._packet, b, 0)
      if not self._parse then
	 b = buffer.allocate()
	 packet.add_iovec(self._packet, b, 0)
	 self._parse = { ulp = nil, offset = 0 }
      end
      -- If the parse stack already exists, its associated iovec was
      -- moved to slot 1 by packet.prepend_iovec()
      self._parse.iovec = 1
      self._push = true
   end
   local sizeof = proto:sizeof()
   local iovec = self._packet.iovecs[0]
   assert(iovec.offset + iovec.length + sizeof <= iovec.buffer.size,
	  "not enough space in buffer to push header")
   proto:copy(iovec.buffer.pointer + iovec.offset + iovec.length)
   iovec.length = iovec.length + sizeof
   self._packet.length = self._packet.length + sizeof
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
   assert(self._parse, "non-parseable datagram")
   local parse = self._parse
   local class = class or parse.ulp
   local iovec = self._packet.iovecs[parse.iovec]

   if not parse.ulp or (class and class ~= parse.ulp) then
      return nil
   end
   local proto = parse.ulp:new_from_mem(iovec.buffer.pointer + iovec.offset
					+ parse.offset, iovec.length - parse.offset)
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
   assert(self._parse, "non-parseable datagram")
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

-- Remove the bottom n elements from the parse stack by adjusting the
-- offset of the relevant iovec.
function datagram:pop (n)
   local n = n or 1
   local parse = self._parse
   assert(parse, "non-parseable datagram") 
   assert(n <= parse.index)
   local proto
   local iovec = self._packet.iovecs[parse.iovec]
   -- Don't use table.remove to avoid garbage
   for i = 1, parse.index do
      if i <= n then
	 proto = parse.stack[i]
	 local sizeof = proto:sizeof()
	 proto:free()
	 iovec.offset = iovec.offset + sizeof
	 iovec.length = iovec.length - sizeof
	 self._packet.length = self._packet.length - sizeof
	 parse.offset = parse.offset - sizeof
      end
      if i+n <= parse.index then
	 parse.stack[i] = parse.stack[i+n]
      else
	 parse.stack[i] = nil
      end
   end
   parse.index = parse.index - n
end

-- Remove <length> bytes from the start of the packet.  It is intended
-- as an efficient version of pop() if the caller already knows what
-- type of header is at the start of the packet, for example after a
-- successful match of matcher:compare().  If the caller also knows
-- the type of the subsequent header, it can pass the corresponding
-- protocol class as second argument to pop_raw().  This will set the
-- datagram's upper-layer protocol to this class such that the parse()
-- method can be used to process the datagram further.
function datagram:pop_raw (length, ulp)
   local iovec = self._packet.iovecs[self._parse.iovec]
   iovec.offset = iovec.offset + length
   iovec.length = iovec.length - length
   self._packet.length = self._packet.length - length
   self._parse.ulp = ulp
end

function datagram:stack ()
   return(self._parse.stack)
end

function datagram:packet ()
   return(self._packet)
end

-- Return the location and size of the packet's payload.  If mem is
-- non-nil, the memory region at the given address and size is
-- appended to the packet's payload first.
function datagram:payload (mem, size)
   local parse = self._parse
   local iovec = self._packet.iovecs[parse.iovec]
   local payload = iovec.buffer.pointer + iovec.offset + parse.offset
   if mem ~= nil then
      assert(size <= iovec.buffer.size - (iovec.offset + iovec.length),
	     "not enough space in buffer to add payload of size "..size)
      ffi.copy(iovec.buffer.pointer + iovec.offset + iovec.length,
	      mem, size)
      iovec.length = iovec.length + size
      self._packet.length = self._packet.length + size
   end
   local p_size = iovec.length - parse.offset
   return payload, p_size
end

return datagram
