module(...,package.seeall)

local ffi = require("ffi")

local app  = require("core.app")
local buffer = require("core.buffer")
local packet = require("core.packet")
local pcap = require("lib.pcap.pcap")

PcapReader = {}

function PcapReader:new (filename)
   local records = pcap.records(filename)
   return setmetatable({iterator = records, done = false},
		       {__index = PcapReader})
end

function PcapReader:pull ()
   assert(self.output.output)
   while not self.done and not app.full(self.output.output) do
      local data, record, extra = self.iterator()
      if data then
         local p = packet.allocate()
         local b = buffer.allocate()
         ffi.copy(b.pointer, data)
         packet.add_iovec(p, b, string.len(data))
         app.transmit(self.output.output, p)
      else
         self.done = true
      end
   end
end

PcapWriter = {}

function PcapWriter:new (filename)
   local file = io.open(filename, "w")
   pcap.write_file_header(file)
   return setmetatable({file = file}, {__index = PcapWriter})
end

function PcapWriter:push ()
   while not app.empty(self.input.input) do
      local p = app.receive(self.input.input)
      pcap.write_record_header(self.file, p.length)
      for i = 0, p.niovecs-1 do
	 local iov = p.iovecs[i]
	 -- XXX expensive to create interned Lua string.
	 self.file:write(ffi.string(iov.buffer.pointer, iov.length))
      end
      self.file:flush()
   end
end

