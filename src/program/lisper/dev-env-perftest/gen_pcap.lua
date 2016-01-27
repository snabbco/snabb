#!snabb/src/snabb snsh
local pcap = require'lib.pcap.pcap'
local eth  = require'lib.protocol.ethernet'
local ipv6 = require'lib.protocol.ipv6'
local ffi  = require'ffi'

local function file(filename)
	local f = io.open(filename, "w")
	pcap.write_file_header(f)
	return f
end

local function write(f, p)
	local buf, len = p.data, p.length
	pcap.write_record_header(f, len)
	print(string.format('writing %d bytes packet', p.length))
	f:write(ffi.string(buf, len))
end

local l2tp_ct = ffi.typeof[[
   struct {
      // ethernet
      char     dmac[6];
      char     smac[6];
      uint16_t ethertype; // dd:86 = ipv6

      // ipv6
      uint32_t flow_id; // version, tc, flow_id
      int16_t  payload_length;
      int8_t   next_header; // 115 = L2TPv3
      uint8_t  hop_limit;
      char     src_ip[16];
      char     dst_ip[16];

      // l2tp
      uint32_t session_id;
      char     cookie[8];

      // tunneled ethernet frame
      char l2tp_dmac[6];
      char l2tp_smac[6];

   } __attribute__((packed))
   ]]

local l2tp_ct_size = ffi.sizeof(l2tp_ct)
local l2tp_ctp = ffi.typeof("$*", l2tp_ct)

local function gen(len, smac, dmac, src_ip, dst_ip, sid, cookie)
   local dp = packet.allocate()
	local hsize = src_ip and l2tp_ct_size or 12
	dp.length = hsize + len
	ffi.copy(dp.data + hsize, ('x'):rep(len))
   local p = ffi.cast(l2tp_ctp, dp.data)
   ffi.copy(p.smac, smac, 6)
   ffi.copy(p.dmac, dmac, 6)
	if src_ip then
		p.ethertype = 0xdd86 --ipv6
		p.flow_id = 0x60 --ipv6
		p.payload_length = htons(len + 12 + 12) --payload + ETH + L2TPv3
		p.next_header = 115 --L2TPv3
		p.hop_limit = 64 --default
		ffi.copy(p.src_ip, src_ip, 16)
		ffi.copy(p.dst_ip, dst_ip, 16)
		p.session_id = htonl(sid)
		ffi.copy(p.cookie, cookie, 8)
	end
   return dp
end

local f = file'lisper01.pcap'
local p = gen(150, '00:00:00:00:02:01', '00:00:00:00:02:02')
write(f, p)
f:close()

local f = file'lisper02.pcap'
for i=1,math.random(100, 200) do
	local smac = eth:pton(smac)
	local dmac = eth:pton(dmac)
	local src_ip = ipv6:pton(scr_ip)
	local dst_ip = ipv6:pton(dst_ip)
	local sid = 1
	local cookie = '\0\0\0\0\0\0\0\0'
	local len = math.random(50, 500)
	gen(len, smac, dmac, src_ip, dst_ip, sid, cookie)
end
f:close()
