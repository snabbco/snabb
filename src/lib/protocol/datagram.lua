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
-- This functionality is provided by keeping track of two separate
-- header stacks, called the "parse stack" and the "push stack".  The
-- parse stack is built from the data contained in an existing packet
-- while the push stack is built from newly created protocol headers.

-- The datagram object keeps track of the start of the yet unparsed
-- portion of a packet by storing the index of the iovec and the
-- offset relative to the iovec's offset into the buffer.  By
-- definition, the unparsed portion of a packet is called the payload
-- at any point in time, i.e. once a header is parsed, it is no longer
-- part of the payload.
--
-- When a new datagram is created, the index and offset are both
-- initialized to zero, such that parsing starts at the beginning of
-- the packet and the entire packet is considered as payload.
--
-- When one of the parser methods is called, the offset is advanced by
-- the size of the parsed header (and the payload reduced
-- correspondingly).
--
-- It is important to note that parsing is currently restricted to a
-- single buffer.  If the total size of a multi-buffer packet is not
-- larger than a single buffer, the buffers can be coalesced into one
-- by passing the "coalesce" option to the datagram constructor.
--
-- Also note that parsing does not change the packet itself.  However,
-- the header at the bottom of the parse stack (which is located at
-- the beginning of the buffer's valid data) can be removed from the
-- packet by calling the pop() method, which advances the iovec's
-- offset accordingly.
--
-- The push stack works differently.  First of all, it is important to
-- note that it grows downwards, i.e. inner headers must be pushed
-- onto the packet before outer headers.  The push mechanism always
-- works on iovec #0.  When this iovec has no room to store the new
-- header adjacent to the beginning of the buffer's valid data, a new
-- buffer is prepended to the packet.  The offset of the new iovec is
-- then set to the size of the buffer to allow downward growth.  When
-- this happens, the iovec index of the parse stack is increased by
-- one to account for the new buffer.
--
-- This on-demand allocation minimizes the number of newly created
-- buffers even if different apps push headers to the same packet.
--
-- By default, when a header is pushed onto a packet, the header data
-- is only copied into the packet, i.e. changes to the header object
-- after the fact are not represented in the packet.  It is also
-- possible to relocate the header object's data to the packet buffer,
-- such that changes to the object are reflected in the packet.  This
-- is useful if certain header fields need to be updated after the
-- header has been pushed.  However, the application must then make
-- sure that the header object is discarded when the packet buffer is
-- released.
--
-- To construct a packet from scratch, the constructor is called
-- without a reference to a packet.  In this case, a new packet is
-- allocated with a single empty buffer.  All methods are applicable
-- to such a datagram.

module(..., package.seeall)
local packet = require("core.packet")
local buffer = require("core.buffer")
local ffi    = require("ffi")

local datagram = subClass(nil)

-- Class methods

-- Create a datagram from a packet or from scratch (if p == nil).  The
-- class argument is only relevant for parsing and can be set to the
-- header class of the the outermost packet header.  
local function init (o, p, class, options)
   if not o._recycled then
      o._parse = { stack = {}, index = 0 }
      o._packet = ffi.new("struct packet *[1]")
      o._opt_default = { coalesce = false }
   elseif o._parse.stack[1] then
      for i, _ in ipairs(o._parse.stack) do
	 o._parse.stack[i]:free()
	 o._parse.stack[i] = nil
      end
      o._parse.index = 0
   end
   o._opt = options or o._opt_default
   o._parse.ulp = class
   if p then
      if o._opt.coalesce then
	 packet.coalesce(p)
      end
      o._packet[0] = p
   else
      o._packet[0] = packet.allocate()
      local b = buffer.allocate()
      packet.add_iovec(o._packet[0], b, 0)
   end
   o._parse.iovec = 0
   o._parse.offset = 0
   return o
end

function datagram:new (p, class, options)
   return(init(datagram:superClass().new(self), p, class, options))
end

-- Reuse an existing object to avoid putting it on the freelist
function datagram:reuse (p, class, options)
   self._recycled = true
   return(init(self, p, class, options))
end

-- Instance methods

-- Push a new protocol header to the front of the packet, i.e. the
-- buffer of iovec #0.  If there is no room for the header, a new
-- buffer is prepended to the packet first.  If relocate is a false
-- value, the protocol's header is copied to the packet.  If it is a
-- true value, the protocol's header is relocated to the buffer
-- instead.
function datagram:push (proto, relocate)
   local iov = self._packet[0].iovecs[0]
   local sizeof = proto:sizeof()
   if sizeof > iov.offset then
      -- Header doesn't fit, allocate a new buffer
      local b = buffer.allocate()
      packet.prepend_iovec(self._packet[0], b, 0, b.size)
      self._parse.iovec = self._parse.iovec+1
   end
   proto:copy(iov.buffer.pointer + iov.offset - sizeof, relocate)
   iov.offset = iov.offset - sizeof
   iov.length = iov.length + sizeof
   self._packet[0].length = self._packet[0].length + sizeof
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
   local iovec = self._packet[0].iovecs[parse.iovec]

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
   assert(n <= parse.index)
   local proto
   local iovec = self._packet[0].iovecs[parse.iovec]
   -- Don't use table.remove to avoid garbage
   for i = 1, parse.index do
      if i <= n then
	 proto = parse.stack[i]
	 local sizeof = proto:sizeof()
	 proto:free()
	 iovec.offset = iovec.offset + sizeof
	 iovec.length = iovec.length - sizeof
	 self._packet[0].length = self._packet[0].length - sizeof
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
   local iovec = self._packet[0].iovecs[self._parse.iovec]
   iovec.offset = iovec.offset + length
   iovec.length = iovec.length - length
   self._packet[0].length = self._packet[0].length - length
   self._parse.ulp = ulp
end

function datagram:stack ()
   return(self._parse.stack)
end

function datagram:packet ()
   return(self._packet[0])
end

-- Return the location and size of the packet's payload.  If mem is
-- non-nil, the memory region at the given address and size is
-- appended to the packet's payload first.  Because parsing is
-- restricted to a single buffer, it is possible that additional
-- buffers exist beyond the parse buffer.  In this case, the payload
-- is not complete.  This is communicated to the caller by a third
-- return value, which is a true value if the payload is complete and
-- a false value if not.
function datagram:payload (mem, size)
   local parse = self._parse
   local iovec = self._packet[0].iovecs[parse.iovec]
   local payload = iovec.buffer.pointer + iovec.offset + parse.offset
   if mem ~= nil then
      assert(size <= iovec.buffer.size - (iovec.offset + iovec.length),
	     "not enough space in buffer to add payload of size "..size)
      ffi.copy(iovec.buffer.pointer + iovec.offset + iovec.length,
	      mem, size)
      iovec.length = iovec.length + size
      self._packet[0].length = self._packet[0].length + size
   end
   local p_size = iovec.length - parse.offset
   return payload, p_size, (parse.iovec == self._packet[0].niovecs - 1)
end

return datagram
