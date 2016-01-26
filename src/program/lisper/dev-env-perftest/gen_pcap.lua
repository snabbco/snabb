#!snabb/src/snabb snsh
local pcap = require'lib.pcap.pcap'
local eth = require'lib.protocol.ethernet'
local dtg = require'lib.protocol.datagram'
local ffi = require'ffi'

local function file(filename)
	local file = io.open(filename, "w")
	pcap.write_file_header(file)
	return file
end

local function write(file, p)
	local buf, len = p.data, p.length
	pcap.write_record_header(file, len)
	print(string.format('writing %d bytes packet', p.length))
	file:write(ffi.string(buf, len))
end

local function gen_eth_eth(f, len)
	local e = eth:new{
		src = eth:pton'00:00:00:00:02:01',
		dst = eth:pton'00:00:00:00:02:02',
		type = 0x86dd,
	}
	local d = dtg:new()
	d:push(e)
	local s = ('x'):rep(len)
	d:payload(s, #s)
	local p = d:packet()
	write(f, p)
end

local function gen_l2tp_l2tp(f, len)
	local e = eth:new{
		src = eth:pton'00:00:00:00:02:01',
		dst = eth:pton'00:00:00:00:02:02',
		type = 0x86dd,
	}
	local d = dtg:new()
	d:push(e)
	local s = ('x'):rep(len)
	d:payload(s, #s)
	local p = d:packet()
	write(f, p)
end

local gen_funcs = {gen_l2tp_l2tp, gen_l2tp_lisper, gen_lisper_l2tp}

local f = file'random.pcap'
for i=1,math.random(100, 200) do
	local gen = gen_funcs(math.random(1, #gen_funcs))
	gen(math.random(50, 500))
end
f:close()
