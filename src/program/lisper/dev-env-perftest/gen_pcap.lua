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
	file:write(ffi.string(buf, len))
	file:flush()
end

local function gen_eth_eth(name, len)
	local f = file(name)
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
	print(p.length)
	write(f, p)
	f:close()
end

gen_eth_eth('eth-eth.pcap', 150)
