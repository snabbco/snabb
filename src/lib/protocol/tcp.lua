module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local header = require("lib.protocol.header")
local ipsum = require("lib.checksum").ipsum

local tcp = subClass(header)

-- Class variables
tcp._name = "tcp"
tcp._ulp = { method = nil }
tcp:init(
   {
      [1] = ffi.typeof[[
	    struct {
	       uint16_t    src_port;
	       uint16_t    dst_port;
	       uint32_t    seq;
	       uint32_t    ack;
	       uint16_t    off_flags; //data offset:4 reserved:3 NS:1 CWR:1 ECE:1 URG:1 ACK:1 PSH:1 RST:1 SYN:1 FIN:1
	       uint16_t    window_size;
	       uint16_t    checksum;
	       uint16_t    pad;
	    } __attribute__((packed))
      ]],
   })

-- Class methods

function tcp:new (config)
   local o tcp:superClass().new(self)
   o:src_port(config.src_port)
   o:dst_port(config.dst_port)
   o:seq_num(config.seq)
   o:ack_num(config.ack)
   o:window_size(config.window_size)
   o:header().pad = 0
   o:offset(config.offset or 0)
   o:ns(config.ns or 0)
   o:cwr(config.cwr or 0)
   o:ece(config.ece or 0)
   o:urg(config.urg or 0)
   o:ack(config.ack or 0)
   o:psh(config.psh or 0)
   o:rst(config.rst or 0)
   o:syn(config.syn or 0)
   o:fin(config.fin or 0)
   o:checksum()
   return o
end

-- Instance methods

function tcp:src_port (port)
   local h = self:header()
   if port ~= nil then
      h.src_port = C.htons(port)
   end
   return C.ntohs(h.src_port)
end

function tcp:dst_port (port)
   local h = self:header()
   if port ~= nil then
      h.dst_port = C.htons(port)
   end
   return C.ntohs(h.dst_port)
end

function tcp:seq_num (seq)
   local h = self:header()
   if seq ~= nil then
      h.seq = C.htonl(seq)
   end
   return C.ntohl(h.seq)
end

function tcp:ack_num (ack)
   local h = self:header()
   if ack ~= nil then
      h.ack = C.htonl(ack)
   end
   return C.ntohl(h.ack)
end

function tcp:offset (offset)
   -- ensure reserved bits are 0
   lib.bitfield(16, self:header(), 'off_flags', 4, 3, 0)

   return lib.bitfield(16, self:header(), 'off_flags', 0, 4, offset)
end

-- set all flags at once
function tcp:flags (flags)
   return lib.bitfield(16, self:header(), 'off_flags', 7, 9, flags)
end

function tcp:ns (ns)
   return lib.bitfield(16, self:header(), 'off_flags', 7, 1, ns)
end

function tcp:cwr (cwr)
   return lib.bitfield(16, self:header(), 'off_flags', 8, 1, cwr)
end

function tcp:ece (ece)
   return lib.bitfield(16, self:header(), 'off_flags', 9, 1, ece)
end

function tcp:urg (urg)
   return lib.bitfield(16, self:header(), 'off_flags', 10, 1, urg)
end

function tcp:ack (ack)
   return lib.bitfield(16, self:header(), 'off_flags', 11, 1, ack)
end

function tcp:psh (psh)
   return lib.bitfield(16, self:header(), 'off_flags', 12, 1, psh)
end

function tcp:rst (rst)
   return lib.bitfield(16, self:header(), 'off_flags', 13, 1, rst)
end

function tcp:syn (syn)
   return lib.bitfield(16, self:header(), 'off_flags', 14, 1, syn)
end

function tcp:fin (fin)
   return lib.bitfield(16, self:header(), 'off_flags', 15, 1, fin)
end

function tcp:window_size (window_size)
   local h = self:header()
   if window_size ~= nil then
      h.window_size = C.htons(window_size)
   end
   return C.ntohs(h.window_size)
end

function tcp:checksum (payload, length, ip)
   local h = self:header()
   if payload then
      local csum = 0
      if ip then
         -- Checksum IP pseudo-header
         local ph = ip:pseudo_header(length + self:sizeof(), 6)
         csum = ipsum(ffi.cast("uint8_t *", ph), ffi.sizeof(ph), 0)
      end
      -- Add TCP header
      h.checksum = 0
      csum = ipsum(ffi.cast("uint8_t *", h),
                   self:sizeof(), bit.bnot(csum))
      -- Add TCP payload
      h.checksum = C.htons(ipsum(payload, length, bit.bnot(csum)))
   end
   return C.ntohs(h.checksum)
end

-- override the default equality method
function tcp:eq (other)
   --compare significant fields
   return (self:src_port() == other:src_port()) and
         (self:dst_port() == other:dst_port()) and
         (self:seq_num() == other:seq_num()) and
         (self:ack_num() == other:ack_num())
end

local function test_tcp_checksum ()
   local ipv4 = require("lib.protocol.ipv4")

   local IP_BASE      = 14
   local IP_HDR_SIZE  = 20
   local TCP_BASE     = IP_BASE + IP_HDR_SIZE
   local TCP_HDR_SIZE = 20
   local PAYLOAD_BASE = TCP_BASE + TCP_HDR_SIZE

   local p = packet.from_string(lib.hexundump([[
      52:54:00:02:02:02 52:54:00:01:01:01 08 00 45 00
      00 34 59 1a 40 00 40 06 00 00 c0 a8 14 a9 6b 15
      f0 b4 de 0b 01 bb e7 db 57 bc 91 cd 18 32 80 10
      05 9f 00 00 00 00 01 01 08 0a 06 0c 5c bd fa 4a
      e1 65
   ]], 66))

   local ip_hdr = ipv4:new_from_mem(p.data + IP_BASE, IP_HDR_SIZE)
   local tcp_hdr = tcp:new_from_mem(p.data + TCP_BASE, TCP_HDR_SIZE)
   local payload_length = p.length - PAYLOAD_BASE
   local csum = tcp_hdr:checksum(p.data + PAYLOAD_BASE, payload_length, ip_hdr)
   assert(csum == 0x382a, "Wrong TCP checksum")
end

function selftest ()
   test_tcp_checksum()
end

tcp.selftest = selftest

return tcp
