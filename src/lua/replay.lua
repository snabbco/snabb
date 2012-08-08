-- replay.lua -- Switch with input from a file, recording output to a file
-- For testing switch behavior from test input files.
-- 
-- Copyright 2012 Snabb GmbH. See the file LICENSE.

module("replay",package.seeall)

local ffi    = require "ffi"

local switch = require "switch"
local port   = require "port"
local Port   = port.Port

function main ()
   if #arg ~= 2 then
      io.stderr:write("Usage: replay <output> <input>")
      os.exit(1)
   end
   local output, input = arg[1], arg[2]
   switch.trace(output)
   for data, header, extra in pcap.records(input) do
      if extra.flags == 0 then -- input frame
	 local frame = ffi.cast("char *", data)
	 local packet = switch.makepacket(extra.port_id, frame, header.orig_len)
	 -- Provision new switch ports on demand
	 if switch.getport(extra.port_id) == nil then
	    switch.addport(extra.port_id, medium.Null)
	 end
	 switch.input(packet)
      end
   end
end

main()
