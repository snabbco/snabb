#!snabb/src/snabb snsh
io.stdout:setvbuf'no'
io.stderr:setvbuf'no'

--L2TP IP-over-IPv6 tunnelling program for testing.

local function assert(v, ...)
   if v then return v, ... end
   error(tostring((...)), 2)
end

local ffi    = require'ffi'
local S      = require'syscall'
local C      = ffi.C
local htons  = require'syscall.helpers'.htons

local DEBUG = os.getenv'DEBUG'

local function hex(s)
   return (s:gsub('(.)(.?)', function(c1, c2)
      return c2 and #c2 == 1 and
         string.format('%02x%02x ', c1:byte(), c2:byte()) or
         string.format('%02x ', c1:byte())
   end))
end

local digits = {}
for i=0,9 do digits[string.char(('0'):byte()+i)] = i end
for i=0,5 do digits[string.char(('a'):byte()+i)] = 10+i end
for i=0,5 do digits[string.char(('A'):byte()+i)] = 10+i end
local function parsehex(s)
   return (s:gsub('[%s%:%.]*(%x)(%x)[%s%:%.]*', function(hi, lo)
      local hi = digits[hi]
      local lo = digits[lo]
      return string.char(lo + hi * 16)
   end))
end

local function open_tap(name)
   local fd = assert(S.open('/dev/net/tun', 'rdwr, nonblock'))
   local ifr = S.t.ifreq{flags = 'tap, no_pi', name = name}
   assert(fd:ioctl('tunsetiff', ifr))
   return fd
end

local function open_raw(name)
   local fd = assert(S.socket('packet', 'raw, nonblock', htons(S.c.ETH_P.all)))
   local ifr = S.t.ifreq{name = name}
   assert(S.ioctl(fd, 'siocgifindex', ifr))
   assert(S.bind(fd, S.t.sockaddr_ll{
      ifindex = ifr.ivalue,
      protocol = 'all'}))
   return fd
end

local mtu = 1500
local rawbuf = ffi.new('uint8_t[?]', mtu)
local tapbuf = ffi.new('uint8_t[?]', mtu)
local function read_buf(buf, fd)
   return buf, assert(S.read(fd, buf, mtu))
end

local function write(fd, s, len)
   assert(S.write(fd, s, len))
end

local tapname, ethname, smac, dmac, sip, dip, sid, did = unpack(main.parameters)
if not (tapname and ethname and smac and dmac and sip and dip and sid and did) then
   print('Usage: l2tp.lua TAP ETH SMAC DMAC SIP DIP SID DID')
   print'   TAP:  the tunneled interface: will be created if not present.'
   print'   ETH:  the tunneling interface: must have an IPv6 assigned.'
   print'   SMAC: the MAC address of ETH.'
   print'   DMAC: the MAC address of the gateway interface.'
   print'   SIP:  the IPv6 of ETH (long form).'
   print'   DIP:  the IPv6 of ETH at the other endpoint (long form).'
   print'   SID:  session ID (hex)'
   print'   DID:  peer session ID (hex)'
   os.exit(1)
end
smac = parsehex(smac)
dmac = parsehex(dmac)
sip  = parsehex(sip)
dip  = parsehex(dip)
sid  = parsehex(sid)
did  = parsehex(did)

local tap = open_tap(tapname)
local raw = open_raw(ethname)

print('tap  ', tapname)
print('raw  ', ethname)
print('smac ', hex(smac))
print('dmac ', hex(dmac))
print('sip  ', hex(sip))
print('dip  ', hex(dip))
print('sid  ', hex(sid))
print('did  ', hex(did))

local l2tp_ct = ffi.typeof[[
struct {

   // ethernet
   char     dmac[6];
   char     smac[6];
   uint16_t ethertype;

   // ipv6
   uint32_t flow_id; // version, tc, flow_id
   int8_t   payload_length_hi;
   int8_t   payload_length_lo;
   int8_t   next_header;
   uint8_t  hop_limit;
   char     src_ip[16];
   char     dst_ip[16];

   // l2tp
   //uint32_t session_id;
   char     session_id[4];
   char     cookie[8];

} __attribute__((packed))
]]

local l2tp_ct_size = ffi.sizeof(l2tp_ct)
local l2tp_ctp = ffi.typeof('$*', l2tp_ct)

local function decap_l2tp_buf(buf, len)
   if len < l2tp_ct_size then return nil, 'packet too small' end
   local p = ffi.cast(l2tp_ctp, buf)
   if p.ethertype ~= 0xdd86 then return nil, 'not ipv6' end
   if p.next_header ~= 115 then return nil, 'not l2tp' end
   local dmac = ffi.string(p.dmac, 6)
   local smac = ffi.string(p.smac, 6)
   local sip = ffi.string(p.src_ip, 16)
   local dip = ffi.string(p.dst_ip, 16)
   local sid = ffi.string(p.session_id, 4) --p.session_id
   local payload_size = len - l2tp_ct_size
   return smac, dmac, sip, dip, sid, l2tp_ct_size, payload_size
end

local function encap_l2tp_buf(smac, dmac, sip, dip, did, payload, payload_size, outbuf)
   local p = ffi.cast(l2tp_ctp, outbuf)
   ffi.copy(p.dmac, dmac)
   ffi.copy(p.smac, smac)
   p.ethertype = 0xdd86
   p.flow_id = 0x60
   local ipsz = payload_size + 12
   p.payload_length_hi = bit.rshift(ipsz, 8)
   p.payload_length_lo = bit.band(ipsz, 0xff)
   p.next_header = 115
   p.hop_limit = 64
   ffi.copy(p.src_ip, sip)
   ffi.copy(p.dst_ip, dip)
   ffi.copy(p.session_id, did)
   ffi.fill(p.cookie, 8)
   ffi.copy(p + 1, payload, payload_size)
   return outbuf, l2tp_ct_size + payload_size
end

--fast select ----------------------------------------------------------------
--select() is gruesome.

local band, bor, shl, shr = bit.band, bit.bor, bit.lshift, bit.rshift

local function getbit(b, bits)
   return band(bits[shr(b, 3)], shl(1, band(b, 7))) ~= 0
end

local function setbit(b, bits)
   bits[shr(b, 3)] = bor(bits[shr(b, 3)], shl(1, band(b, 7)))
end

ffi.cdef[[
typedef struct {
   uint8_t bits[128]; // 1024 bits
} xfd_set;
int xselect(int, xfd_set*, xfd_set*, xfd_set*, void*) asm("select");
]]
local function FD_ISSET(d, set) return getbit(d, set.bits) end
local function FD_SET(d, set)
   assert(d <= 1024)
   setbit(d, set.bits)
end
local fds0 = ffi.new'xfd_set'
local fds  = ffi.new'xfd_set'
local fds_size = ffi.sizeof(fds)
local rawfd = raw:getfd()
local tapfd = tap:getfd()
FD_SET(rawfd, fds0)
FD_SET(tapfd, fds0)
local maxfd = math.max(rawfd, tapfd) + 1
local EINTR = 4
local function can_read() --returns true if fd has data, false if timed out
   ffi.copy(fds, fds0, fds_size)
   ::retry::
   local ret = C.xselect(maxfd, fds, nil, nil, nil)
   if ret == -1 then
      if C.errno() == EINTR then goto retry end
      error('select errno '..tostring(C.errno()))
   end
   return FD_ISSET(rawfd, fds), FD_ISSET(tapfd, fds)
end

------------------------------------------------------------------------------

while true do
   local can_raw, can_tap = can_read()
   if can_raw or can_tap then
      if can_raw then
         local buf, len = read_buf(rawbuf, raw)
         local smac1, dmac1, sip1, dip1, did1, payload_offset, payload_size = decap_l2tp_buf(buf, len)
         local accept = smac1
            and smac1 == dmac
            and dmac1 == smac
            and dip1 == sip
            and sip1 == dip
            and did1 == sid
         if DEBUG then
            if accept or smac1 then
               print('read', accept and 'accepted' or 'rejected')
               print('  smac ', hex(smac1))
               print('  dmac ', hex(dmac1))
               print('  sip  ', hex(sip1))
               print('  dip  ', hex(dip1))
               print('  did  ', hex(did1))
               print('  #    ', payload_size)
            end
         end
         if accept then
            write(tap, buf + payload_offset, payload_size)
         end
      end
      if can_tap then
         local payload, payload_size = read_buf(tapbuf, tap)
         local frame, frame_size = encap_l2tp_buf(smac, dmac, sip, dip, did, payload, payload_size, rawbuf)
         if DEBUG then
            print('write')
            print('  smac ', hex(smac))
            print('  dmac ', hex(dmac))
            print('  sip  ', hex(sip))
            print('  dip  ', hex(dip))
            print('  did  ', hex(did))
            print('  #in  ', payload_size)
            print('  #out ', frame_size)
         end
         write(raw, frame, frame_size)
      end
   end
end

tap:close()
raw:close()
