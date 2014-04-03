module(...,package.seeall)

local debug = false

local ffi = require("ffi")
local C = ffi.C

local buffer   = require("core.buffer")
local freelist = require("core.freelist")
local memory   = require("core.memory")

require("core.packet_h")

initial_fuel = 1000
max_packets = 1e6
packets_fl = freelist.new("struct packet *", max_packets)
packets    = ffi.new("struct packet[?]", max_packets)

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

-- fill's an allocated packet with data from a string
function fill_data(p, d, offset)
   offset = offset or 0
   local iovec = p.iovecs[0]
   assert (offset+#d <= iovec.length, "can't fit on first iovec")       -- TODO: handle more iovecs
   ffi.copy (iovec.buffer.pointer + iovec.offset + offset, d, #d)
end

-- creates a packet from a given binary string
function from_data(d)
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
      assert(p.refcount >= n)
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
   ffi.fill(p, ffi.sizeof("struct packet"), 0)
   p.refcount       = 1
   p.fuel           = initial_fuel
   freelist.add(packets_fl, p)
end

function iovec_dump(iovec)
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

function report(p)
   print (string.format([[
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
   ))
   for i = 0, p.niovecs-1 do
      print(string.format([[
            iovec #%d: %s
         ]], i, iovec_dump(p.iovecs[i])))
   end
end

module_init()
