-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

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
--   Appending payload to a packet
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
-- Note that parsing does not change the packet itself.  However, the
-- header at the bottom of the parse stack (which is located at the
-- beginning of the buffer's valid data) can be removed from the
-- packet by calling the pop() method, which truncates the underlying
-- packet accordingly.
--
-- The push() method can be used to prepend headers in front of the
-- packet.
--
-- A datagram can be used in two modes of operation, called "immediate
-- commit" and "delayed commit".  In immediate commit mode, the
-- push*() and pop*() methods immediately modify the underlying
-- packet.  However, this can be undesireable.
--
-- Even though the manipulations are relatively fast by using SIMD
-- instructions to move and copy data when possible, performance-aware
-- applications usually try to avoid as much of them as possible.
-- This creates a conflict if the caller performs operations to push
-- or parse a sequence of protocol headers in immediate commit mode.
--
-- This problem can be avoided by using delayed commit mode.  In this
-- mode, the push*() methods add the data to a separate buffer as
-- intermediate storage.  The buffer is prepended to the actual packet
-- in a single operation by calling the commit() method.
--
-- The pop*() methods are made light-weight in delayed commit mode by
-- keeping track of an additional offset that indicates where the
-- actual packet starts in the packet buffer.  Each call to one of the
-- pop*() methods simply increases the offset by the size of the
-- popped piece of data.  The accumulated actions will be applied as a
-- single operation by the commit() method.
--
-- The push*() and pop*() methods can be freely mixed in delayed
-- commit mode.
--
-- Due to the destructive nature of these methods in immediate commit
-- mode, they cannot be applied when the parse stack is not empty,
-- because moving the data in the packet buffer will invalidate the
-- parsed headers.  The push*() and pop*() methods will raise an error
-- in that case.
--
-- The buffer used in delayed commit mode has a fixed size of 512
-- bytes.  This limits the size of data that can be pushed in a single
-- operation.  A sequence of push/commit operations can be used to
-- push an arbitrary amount of data in chunks of up to 512 bytes.
--
-- To construct a packet from scratch, the constructor is called
-- without a reference to a packet.  In this case, a new empty packet
-- is allocated.  All methods are applicable to such a datagram.

module(..., package.seeall)
local packet = require("core.packet")
local ffi    = require("ffi")
local C = ffi.C

local datagram = subClass(nil)
datagram._name = 'datagram'
datagram.push_buffer_size = 512

-- Class methods

-- Create a datagram from a packet or from scratch (if p == nil).  The
-- class argument is only relevant for parsing and can be set to the
-- header class of the outermost packet header.  <options> is a table
-- used to pass configuration options to the constructor:
--
--   options = {
--        delayed_commit = true|false, -- default false
--   }
--
-- If a datagram instance is recycled, any protocol headers still on
-- the parse stack are freed.
local empty = {}
local push_buffer_type = ffi.typeof("uint8_t [?]")
function datagram:new (p, class, options)
   local options = options or empty
   local o = datagram:superClass().new(self)
   if not o._recycled then
      o._parse = { stack = {}, index = 0 }
      o._push = { buffer = push_buffer_type(datagram.push_buffer_size) }
      o._packet = ffi.new("struct packet *[1]")
   elseif o._parse.index > 0 then
      local parse = o._parse
      for i = 1, parse.index do
         parse.stack[i]:free()
         parse.stack[i] = nil
      end
      o._parse.index = 0
   end
   o._offset = 0
   o._parse.offset = 0
   o._push.offset = datagram.push_buffer_size
   o._push.size = 0
   o._parse.ulp = class
   o._delayed_commit = options.delayed_commit
   o._packet[0] = p or packet.allocate()
   return o
end

-- Instance methods

-- Push a new protocol header to the front of the packet.
function datagram:push (proto)
   self:push_raw(proto:header(), proto:sizeof())
end

-- Push <length> bytes pointed to by <data> to the front of the
-- packet.  An error is raised if the datagram uses immediate commit
-- mode and the parse stack is not empty.
function datagram:push_raw (data, length)
   if self._delayed_commit then
      local push = self._push
      assert(length <= push.offset)
      push.offset = push.offset - length
      push.size = push.size + length
      ffi.copy(push.buffer + push.offset, data, length)
   else
      -- The memmove() would invalidate the data pointer of headers
      -- that have already been parsed.
      assert(self._parse.index == 0, "parse stack not empty")
      self._packet[0] = packet.prepend(self._packet[0],
                                       ffi.cast("uint8_t *", data), length)
      self._parse.offset = self._parse.offset + length
   end
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
   local proto = class:new_from_mem(self._packet[0].data + parse.offset,
                                    self._packet[0].length - parse.offset)
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

-- Remove <length> bytes from the start of the packet and set
-- upper-layer protocol to <ulp> if <ulp> is supplied.  An error is
-- raised if the datagram operates in immediate commit mode but the
-- parse stack is not empty.
function datagram:pop_raw (length, ulp)
   if self._delayed_commit then
      self._offset = self._offset + length
      self._parse.offset = self._parse.offset + length
   else
      -- The memmove() would invalidate the data pointer of headers
      -- that have already been parsed.
      assert(self._parse.index == 0, "parse stack not empty")
      self._packet[0] = packet.shiftleft(self._packet[0], length)
   end
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
   if mem then packet.append(self._packet[0],
                             ffi.cast("uint8_t *", mem), size) end
   return self._packet[0].data + self._parse.offset,
          self._packet[0].length - self._parse.offset
end

-- Return the location and size of the entire packet buffer
function datagram:data ()
   local p = self._packet
   return p[0].data, p[0].length
end

-- Commit the changes induced by previous calles to the push*() and
-- pop*() methods to the packet data.  An error is raised if the parse
-- stack is not empty.
function datagram:commit ()
   if self._delayed_commit then
      assert(self._parse.index == 0, "parse stack not empty")
      local p = self:packet()
      local offset = self._offset
      local push = self._push
      C.memmove(p.data + push.size, p.data + offset, p.length - offset)
      ffi.copy(p.data, push.buffer + push.offset, push.size)
      local diff = offset - push.size
      p.length = p.length - diff

      self._parse.offset = self._parse.offset - diff
      push.offset = datagram.push_buffer_size
      push.size = 0
      self._offset = 0
   end
end

function selftest ()
   local ethernet = require("lib.protocol.ethernet")
   local ipv6 = require("lib.protocol.ipv6")
   local l2tpv3 = require("lib.protocol.keyed_ipv6_tunnel")

   local mac_addr = ethernet:pton('00:00:00:00:00:00')
   local ether = ethernet:new({ src = mac_addr, dst = mac_addr,
                                type = 0x86dd })
   local ip_addr = ipv6:pton('::1')
   local ip = ipv6:new({ src = ip_addr, dst = ip_addr,
                         next_header = 115 })
   local l2tp = l2tpv3:new()
   local p = packet.allocate()
   local data_size = 512
   local data = ffi.new("uint8_t [?]", data_size)

   -- Check immediate commit semantics
   local dgram = datagram:new(p)
   dgram:push(l2tp)
   dgram:push(ip)
   dgram:push(ether)
   p = dgram:packet()
   local _, p_size = dgram:payload(data, data_size)
   assert(p_size == data_size)
   local _, d_size = dgram:data()
   assert(d_size == ether:sizeof() + ip:sizeof() + l2tp:sizeof() + data_size)

   -- Parse the pushed headers
   dgram:new(p, ethernet)
   assert(ether:eq(dgram:parse()))
   assert(ip:eq(dgram:parse()))
   assert(l2tp:eq(dgram:parse()))
   _, p_size = dgram:payload()
   assert(p_size == data_size)

   -- Check delayed commit semantics.  The packet still contains the
   -- data added above.
   dgram:new(p, ethernet, { delayed_commit = true })
   local mac_addr2 = ethernet:pton('00:00:00:00:00:01')
   local ether2 = ethernet:new({ src = mac_addr2, dst = mac_addr2,
                                 type = 0x86dd })
   local ip_addr2 = ipv6:pton('::2')
   local ip2 = ipv6:new({ src = ip_addr2, dst = ip_addr2,
                       next_header = 115 })
   dgram:push(ip2)
   dgram:push(ether2)
   local stack = dgram:stack()
   assert(#stack == 0)
   assert(ether:eq(dgram:parse()))
   assert(ip:eq(dgram:parse()))
   dgram:pop(2)
   dgram:commit()
   _, d_size = dgram:data()
   assert(d_size == ether2:sizeof() + ip2:sizeof() + l2tp:sizeof() + data_size)
   dgram:new(dgram:packet(), ethernet, { delayed_commit = true })
   assert(ether2:eq(dgram:parse()))
   assert(ip2:eq(dgram:parse()))
   assert(l2tp:eq(dgram:parse()))
   dgram:pop(3)
   dgram:pop_raw(data_size)
   dgram:commit()
   _, d_size = dgram:data()
   assert(d_size == 0, d_size)
end

datagram.selftest = selftest

return datagram
