-- tester.lua -- Test switch operation by post-processing trace files.
-- Copright 2012 Snabb GmbH

module("tester",package.seeall)

local ffi  = require("ffi")
local pcap = require("pcap")
local C    = ffi.C

if #arg ~= 1 then
   print "Usage: tester <pcapfile>"
   print ""
   print "Test that the switching behaviour in pcapfile is correct."
   return
end

local file = io.open(arg[1], "r")
local pcap_file   = ffi.new("struct pcap_file")
local pcap_record = ffi.new("struct pcap_record")
local pcap_extra  = ffi.new("struct pcap_record_extra")

print("filename = " .. arg[1] .. " " .. #arg)
print(ffi.cast("struct pcap_file *", file:read(ffi.sizeof("struct pcap_file"))))

function main ()
   local input, outputs = nil, {}
   for packet, header, extra in pcap.records(arg[1]) do
      if extra.flags == 0 then
	 if input ~= nil then
	    check(input, outputs)
	 end
	 input = {port = extra.port_id, packet = packet}
	 outputs = {}
      else
	 table.insert(outputs, {port = extra.port_id, packet = packet})
      end
--      print(#packet, header, extra, extra.port_id, extra.flags)
   end
end

local success = 0

function check (input, outputs)
   check_no_loop(input, outputs)
   success = success + 1
end

function check_no_loop (input, outputs)
   for _,output in ipairs(outputs) do
      if input.port == output.port then
	 fail(input, outputs, "Loop error on port " .. input.port)
      end
   end
end

function fail (input, outputs, reason)
   print(reason)
--   os.exit(1)
end

main()

print("Success! with " .. success .. " transaction(s)")

