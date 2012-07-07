module(...,package.seeall)

require("shm")

local ffi = require("ffi")
local fabric = ffi.load("fabric")
local dev = fabric.open_shm("/tmp/ba")
local rx = dev.vm2host
local tx = dev.host2vm

ffi.cdef("int usleep(unsigned long usec);")

local echo = true

print("writing pcap file..")
file = io.open("/tmp/x.pcap", "w+")
pcap.write_file_header(file)

while true do
   if shm.available(rx) then
      print("Writing a " .. shm.packet(rx).length .. " byte packet..")
      local rxpacket = rx.packets[rx.head]
      pcap.write_record(file, rxpacket.data, rxpacket.length)
      file:flush()
      if echo then
	 if shm.full(tx) then
	    print("tx overflow")
	 else
	    local txpacket = shm.packet(tx)
	    txpacket.data   = rxpacket.data
	    txpacket.length = rxpacket.length
	    shm.advance_tail(tx)
	    print("successful tx")
	 end
      end
      shm.advance_head(rx)
   else
      -- print("nuthin' doin' " .. rx.head .. " " .. rx.tail)
      ffi.C.usleep(10000)
   end
end
