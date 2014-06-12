module(...,package.seeall)

local debug = false

local ffi = require("ffi")
local C = ffi.C

local buffer   = require("core.buffer")
local freelist = require("core.freelist")
local lib      = require("core.lib")
local memory   = require("core.memory")

require("core.packet_h")

local initial_fuel = 1000
local max_packets = 1e6
local packets_fl = freelist.new("struct packet *", max_packets)
local packets    = ffi.new("struct packet[?]", max_packets)
local packet_size = ffi.sizeof("struct packet")

function module_init ()
   for i = 0, max_packets-1 do
      free(packets[i])
   end
end

-- Return a packet, or nil if none is available.
function allocate ()
   return freelist.remove(packets_fl) or error("out of packets")
end

-- Append data to a packet.
function add_iovec (p, b, length,  offset)
   if debug then assert(p.niovecs < C.PACKET_IOVEC_MAX, "packet iovec overflow") end
   offset = offset or 0
   if debug then assert(length + offset <= b.size) end
   local iovec = p.iovecs[p.niovecs]
   iovec.buffer = b
   iovec.length = length
   iovec.offset = offset
   p.niovecs = p.niovecs + 1
   p.length = p.length + length
end

-- Prepend data to a packet.
function prepend_iovec (p, b, length,  offset)
   if debug then assert(p.niovecs < C.PACKET_IOVEC_MAX, "packet iovec overflow") end
   offset = offset or 0
   if debug then assert(length + offset <= b.size) end
   for i = p.niovecs, 1, -1 do
      ffi.copy(p.iovecs[i], p.iovecs[i-1], ffi.sizeof("struct packet_iovec"))
   end
   local iovec = p.iovecs[0]
   iovec.buffer = b
   iovec.length = length
   iovec.offset = offset
   p.niovecs = p.niovecs + 1
   p.length = p.length + length
end

function niovecs (p)
   return p.niovecs
end

function iovec (p, n)
   return p.iovecs[n]
end

-- Merge all buffers into one. Throws an exception if a single buffer
-- cannot hold the entire packet.
--
-- XXX Should work also with packets that are bigger than a single
-- buffer, i.e. reduce the number of buffers to the minimal set
-- required to hold the entire packet.
function coalesce (p)
   if p.niovecs == 1 then return end
   local b = buffer.allocate()
   assert(p.length <= b.size, "packet too big to coalesce")
   local length = 0
   for i = 0, p.niovecs-1, 1 do
      local iovec = p.iovecs[i]
      ffi.copy(b.pointer + length, iovec.buffer.pointer + iovec.offset, iovec.length)
      buffer.free(iovec.buffer)
      length = length + iovec.length
   end
   p.niovecs, p.length = 0, 0
   add_iovec(p, b, length)
end

-- The same as coalesce(), but allocate new packet
-- while leaving original packet unchanged
function clone (p)
   local new_p = allocate()
   local b = buffer.allocate()
   assert(p.length <= b.size, "packet too big to coalesce")

   local length = 0
   for i = 0, p.niovecs - 1 do
      local iovec = p.iovecs[i]
      ffi.copy(b.pointer + length, iovec.buffer.pointer + iovec.offset, iovec.length)
      length = length + iovec.length
   end
   add_iovec(new_p, b, length)
   return new_p
end

-- The opposite of coalesce
-- Scatters the data through chunks
function scatter (p, sg_list)
   assert(#sg_list + 1 <= C.PACKET_IOVEC_MAX)
   local cloned = clone(p) -- provide coalesced copy
   local result = allocate()
   local iovec = cloned.iovecs[0]
   local offset = 0 -- the offset in the cloned buffer

   -- always append one big chunk in the end, to cover the case
   -- where the supplied sgs are not sufficient to hold all the data
   -- also if we get an empty sg_list this will make a single iovec packet
   local pattern_list = lib.deepcopy(sg_list)
   pattern_list[#pattern_list + 1] = {4096}

   for _,sg in ipairs(pattern_list) do
      local sg_len = sg[1]
      local sg_offset = sg[2] or 0
      local b = buffer.allocate()

      assert(sg_len + sg_offset <= b.size)
      local to_copy = math.min(sg_len, iovec.length - offset)
      ffi.copy(b.pointer + sg_offset, iovec.buffer.pointer + iovec.offset + offset, to_copy)
      add_iovec(result, b, to_copy, sg_offset)

      -- advance the offset in the source buffer
      offset = offset + to_copy
      assert(offset <= iovec.length)
      if offset == iovec.length then
         -- we don't have more data to copy
         break
      end
   end
   packet.deref(cloned)
   return result
end

-- use this function if you want to modify a packet received by an app
-- you cannot modify a packet if it is owned more then one app
-- it will create a copy for you as needed
function want_modify (p)
   if p.refcount == 1 then
      return p
   end
   local new_p = clone(p)
   packet.deref(p)
   return new_p
end

-- fill's an allocated packet with data from a string
function fill_data (p, d, offset)
   offset = offset or 0
   local iovec = p.iovecs[0]
   assert (offset+#d <= iovec.length, "can't fit on first iovec")       -- TODO: handle more iovecs
   ffi.copy (iovec.buffer.pointer + iovec.offset + offset, d, #d)
end

-- creates a packet from a given binary string
function from_data (d)
   local p = allocate()
   local b = buffer.allocate()
   local size = math.min(#d, b.size)
   add_iovec(p, b, size)
   fill_data(p, d)
   return p
end

-- Increase the reference count for packet p by n (default n=1).
function ref (p,  n)
   if p.refcount > 0 then
      p.refcount = p.refcount + (n or 1)
   end
   return p
end

-- Decrease the reference count for packet p.
-- The packet will be recycled if the reference count reaches 0.
function deref (p,  n)
   n = n or 1
   if p.refcount > 0 then
      -- assert(p.refcount >= n)
      if n == p.refcount then
         free(p)
      else
         p.refcount = p.refcount - n
      end
   end
end

-- Tenured packets are not reused by defref().
function tenure (p)
   p.refcount = 0
end

-- Free a packet and all of its buffers.
function free (p)
   for i = 0, p.niovecs-1 do
      buffer.free(p.iovecs[i].buffer)
   end

   p.niovecs        = 0
   p.refcount       = 1
   p.fuel           = initial_fuel
   freelist.add(packets_fl, p)
end

function iovec_dump (iovec)
   local b = iovec.buffer
   local l = math.min(iovec.length, b.size-iovec.offset)
   if l < 1 then return '' end
   o={[-1]=string.format([[
         offset: %d
         length: %d
         buffer.pointer: %s
         buffer.physical: %X
         buffer.size: %d
      ]], iovec.offset, iovec.length, b.pointer, tonumber(b.physical), b.size)}
   for i = 0, l-1 do
      o[i] = bit.tohex(b.pointer[i+iovec.offset], -2)
   end
   return table.concat(o, ' ', -1, l-1)
end

function report (p)
   local result = string.format([[
         refcount: %d
         fuel: %d
         info.flags: %X
         info.gso_flags: %X
         info.hdr_len: %d
         info.gso_size: %d
         info.csum_start: %d
         info.csum_offset: %d
         niovecs: %d
         length: %d
      ]],
      p.refcount, p.fuel, p.info.flags, p.info.gso_flags,
      p.info.hdr_len, p.info.gso_size, p.info.csum_start,
      p.info.csum_offset, p.niovecs, p.length
   )
   for i = 0, p.niovecs-1 do
      result = result .. string.format([[
            iovec #%d: %s
         ]], i, iovec_dump(p.iovecs[i]))
   end

   return result
end

module_init()
