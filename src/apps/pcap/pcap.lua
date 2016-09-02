-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local ffi = require("ffi")

local app  = require("core.app")
local link = require("core.link")
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
   local limit = engine.pull_npackets
   while limit > 0 and not self.done do
      limit = limit - 1
      local data, record, extra = self.iterator()
      if data then
         local p = packet.from_string(data)
         link.transmit(self.output.output, p)
      else
         self.done = true
      end
   end
end

PcapWriter = {}

function PcapWriter:new (filename, arg)
   local conf = arg and config.parse_app_arg(arg) or {}
   local mode = conf.overwrite and "w+" or "w"
   local file, errno = io.open(filename, mode)
   if errno then error(errno) end
   pcap.write_file_header(file)
   return setmetatable({file = file}, {__index = PcapWriter})
end

function PcapWriter:push ()
   while not link.empty(self.input.input) do
      local p = link.receive(self.input.input)
      pcap.write_record_header(self.file, p.length)
      -- XXX expensive to create interned Lua string.
      self.file:write(ffi.string(p.data, p.length))
      self.file:flush()
      packet.free(p)
   end
end

