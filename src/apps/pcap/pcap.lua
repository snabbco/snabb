module(...,package.seeall)

local ffi = require("ffi")

local app  = require("core.app")
local buffer = require("core.buffer")
local packet = require("core.packet")
local pcap = require("lib.pcap.pcap")

Pcap = {}

function Pcap:new (filename)
   local records = pcap.records(filename)
   return setmetatable({iterator = records, done = false}, {__index = Pcap})
end

function Pcap:pull ()
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

