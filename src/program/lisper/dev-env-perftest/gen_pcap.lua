#!snabb/src/snabb snsh
local pcap = require'lib.pcap.pcap'
local eth  = require'lib.protocol.ethernet'
local ipv6 = require'lib.protocol.ipv6'
local ffi  = require'ffi'
local lib  = require'core.lib'

local f
local function file(filename)
	if f then f:close() end
	if not filename then return end
	print('opening '..filename)
	f = io.open(filename, "w")
	pcap.write_file_header(f)
end

local function write(p)
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

local function gen(len, smac, dmac, src_ip, dst_ip, sid, cookie, l2tp_smac, l2tp_dmac)
	local dp = packet.allocate()
	local hsize = src_ip and l2tp_ct_size or 12
	dp.length = hsize + len
	ffi.copy(dp.data + hsize, ('x'):rep(len))
	local p = ffi.cast(l2tp_ctp, dp.data)
	ffi.copy(p.smac, eth:pton(smac), 6)
	ffi.copy(p.dmac, eth:pton(dmac), 6)
	if src_ip then
		p.ethertype = 0xdd86 --ipv6
		p.flow_id = 0x60 --ipv6
		p.payload_length = lib.htons(len + 12 + 12) --payload + ETH + L2TPv3
		p.next_header = 115 --L2TPv3
		p.hop_limit = 64 --default
		ffi.copy(p.src_ip, ipv6:pton(src_ip), 16)
		ffi.copy(p.dst_ip, ipv6:pton(dst_ip), 16)
		p.session_id = lib.htonl(sid)
		ffi.copy(p.cookie, cookie, 8)
		ffi.copy(p.l2tp_smac, eth:pton(l2tp_smac), 6)
		ffi.copy(p.l2tp_dmac, eth:pton(l2tp_dmac), 6)
	end
	write(dp)
end

file'lisper01.pcap'
gen(150, '00:00:00:00:02:01', '00:00:00:00:02:02')

file'lisper02.pcap'
local n = math.random(100, 200)
for i=1,n do
	local len = math.random(20, 200)
	local cookie = '\0\0\0\0\0\0\0\0'
	gen(len, '00:00:00:00:00:21', '00:00:00:00:00:01', 'fd80::21', 'fd80::01', 1, cookie, '00:00:00:00:01:01', '00:00:00:00:01:02')
	gen(len, '00:00:00:00:00:22', '00:00:00:00:00:01', 'fd80::22', 'fd80::01', 1, cookie, '00:00:00:00:01:02', '00:00:00:00:01:01')
end

file()
