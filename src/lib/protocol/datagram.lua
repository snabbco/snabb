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
-- In each case, the headers themselves are always located in the
-- actual packet buffers.  The topmost protocol header on each stack
-- defines which protocol type is expected next.  This is referred to
-- as the "upper-layer protocol" (ULP).  For the parse stack, it
-- defines how the next call of the parse() method will interpret the
-- next piece of the packet data.  For the push stack, it provides a
-- consistency check for the next call of the push() method.
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

require("class")
local packet = require("core.packet")
local buffer = require("core.buffer")

local datagram = subClass(nil)

-- Class methods

-- When the constructor is called with an existing packet, the
-- packet's buffers are coalesced into one and the parse stack is
-- initialized for it.  If p == nil, a new empty packet is allocated.
-- The allocation of buffers is delayed until the first call of the
-- push() method.
function datagram:_init_new(p, class)
   if p then
      packet.coalesce(p)
      self._parse = { stack = {},
		      ulp = class,
		      iovec = 0,
		      offset = 0 }
   else
      p = packet.allocate()
   end
   self._packet = p
end

-- Instance methods

-- Add a new protocol header to the push stack, creating the stack
-- first if it doesn't exist.  If there is no parse stack either,
-- we're dealing with a datagram that has been created from scratch.
-- In this case, we add another empty buffer and set the ULP to nil,
-- which makes this packet effectively non-parseable, but it can still
-- hold the packet's payload.  The method returns the input for
-- convenience.
function datagram:push(proto)
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
      push = { stack = {} }
      self._push = push
   else
      assert(proto:isa(push.ulp), "header type "..proto:name()
       .." does not match expected ulp "..push.ulp:name())
   end
   local sizeof = proto:sizeof()
   local iovec = self._packet.iovecs[0]
   assert(iovec.offset + iovec.length + sizeof <= iovec.buffer.size,
	  "not enough space in buffer to push header of type " ..proto:name())
   proto:moveto(iovec.buffer.pointer + iovec.offset + iovec.length)
   iovec.length = iovec.length + sizeof
   table.insert(push.stack, proto)
   push.ulp = proto:upper_layer()
   return proto
end

-- Create a protocol header from the packet's payload according to the
-- current ULP and push it onto the parse stack. Returns the newly
-- created protocol object.
function datagram:parse_foo()
   assert(self._parse, "non-parseable datagram")
   local parse = self._parse
   if not parse.ulp then return nil end
   local sizeof = parse.ulp:sizeof()
   local iovec = self._packet.iovecs[parse.iovec]
   local proto = parse.ulp:new_from_mem(iovec.buffer.pointer + iovec.offset
					+ parse.offset, iovec.length - parse.offset)
   table.insert(parse.stack, proto)
   parse.ulp = proto:upper_layer()
   parse.offset = parse.offset + sizeof
   return proto
end

-- Create protocol header objects from the packet's payload.  If
-- called with argument nil and the packets ULP is non-nil, a single
-- protocol header of type ULP is created.  The caller can specify
-- matching criteria by passing an array of templates to match for
-- each parsed header.  Each criteria consists of a reference to a
-- header class to match and a function that is evaluated with the
-- protocol object as input.  A header is only pushed onto the parse
-- stack if it matches the class and the function returns a true
-- value.  The class and function can both be nil to provide "wildcard
-- matching".  For example, the following code fragment will match a
-- packet that contains an ethernet header, followed by an arbitrary
-- (but supported) header, followed by an icmp header of type 135.
--
-- local eth = require("lib.protocol.ethernet")
-- local icmp = require("lib.protocol.icmp")
-- dgram:parse({ { ethernet, nil }, { nil, nil },
--               { icmp, function(icmp) return(icmp:type() == 135) end } })
--
-- The method returns the protocl object of the last parsed header or
-- nil if either an unsupported ULP is encountered or one of the match
-- criteria is not met.
function datagram:parse(seq)
   assert(self._parse, "non-parseable datagram")
   local parse = self._parse
   local seq = seq or { { parse.ulp } }
   local proto
   local iovec = self._packet.iovecs[parse.iovec]

   for _, elt in ipairs(seq) do
      local class, check = unpack(elt)
      if not parse.ulp or (class and class ~= parse.ulp) then
	 return nil
      end
      local sizeof = parse.ulp:sizeof()
      proto = parse.ulp:new_from_mem(iovec.buffer.pointer + iovec.offset
				     + parse.offset, iovec.length - parse.offset)
      if check and not check(proto) then
	 return nil
      end
      table.insert(parse.stack, proto)
      parse.ulp = proto:upper_layer()
      parse.offset = parse.offset + sizeof
   end
   return proto
end

-- Undo the last n calls to parse, returning the associated headers to
-- the packet's payload.
function datagram:unparse(n)
   assert(self._parse, "non-parseable datagram")
   local parse = self._parse
   local proto
   while n > 0 and #parse.stack ~= 0 do
      proto = table.remove(parse.stack)
      parse.offset = parse.offset - proto:sizeof()
      parse.ulp = proto:class()
      n = n - 1
   end
end

-- Remove the bottom n elements from the parse stack by adjusting the
-- offset of the relevant iovec.  Returns the last popped protocol
-- object.
function datagram:pop(n)
   local parse = self._parse
   assert(parse, "non-parseable datagram") 
   local proto
   local iovec = self._packet.iovecs[parse.iovec]
   while n > 0 and #parse.stack ~= 0 do
      proto = table.remove(parse.stack, 1)
      local sizeof = proto:sizeof()
      iovec.offset = iovec.offset + sizeof
      iovec.length = iovec.length - sizeof
      n = n - 1
   end
   return proto
end

function datagram:stack()
   return(self._parse.stack)
end

function datagram:packet()
   return(self._packet)
end

-- Return the location and size of the packet's payload.  If mem is
-- non-nil, the memory region at the given address and size is
-- appended to the packet's payload first.
function datagram:payload(mem, size)
   local parse = self._parse
   local iovec = self._packet.iovecs[parse.iovec]
   local payload = iovec.buffer.pointer + iovec.offset + parse.offset
   local p_size = iovec.length - parse.offset
   if mem ~= nil then
      assert(size <= iovec.buffer.size - (iovec.offset + iovec.length),
	     "not enough space in buffer to add payload of size "..size)
      ff.copy(iovec.buffer.pointer + iovec.offset + iovec.length,
	      mem, size)
      p_size = p_size + size
   end
   return payload, p_size
end

return datagram
