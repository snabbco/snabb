-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local ffi = require("ffi")

local app  = require("core.app")
local lib  = require("core.lib")
local link = require("core.link")
local pcap = require("lib.pcap.pcap")
local pf = require("pf")

Tap = {}

local tap_config_params = {
   -- Name of file to which to write packets.
   filename = { required=true },
   -- "truncate" to truncate the file, or "append" to add to the file.
   mode = { default = "truncate" },
   -- Only packets that match this pflang filter will be captured.
   filter = { },
   -- Only write every Nth packet that matches the filter.
   sample = { default=1 },
}

function Tap:new(conf)
   local o = lib.parse(conf, tap_config_params)
   local mode = assert(({truncate='w+b', append='a+b'})[o.mode])
   o.file = assert(io.open(o.filename, mode))
   if o.file:seek() == 0 then pcap.write_file_header(o.file) end
   if o.filter then o.filter = pf.compile_filter(o.filter) end
   o.n = o.sample - 1
   return setmetatable(o, {__index = Tap})
end

function Tap:push ()
   local n = self.n
   while not link.empty(self.input.input) do
      local p = link.receive(self.input.input)
      if not self.filter or self.filter(p.data, p.length) then
         n = n + 1
         if n == self.sample then
            n = 0
            pcap.write_record(self.file, p.data, p.length)
         end
      end
      link.transmit(self.output.output, p)
   end
   self.n = n
end

function selftest ()
   print('selftest: apps.pcap.tap')

   local config = require("core.config")
   local Sink = require("apps.basic.basic_apps").Sink
   local PcapReader = require("apps.pcap.pcap").PcapReader

   local function run(filter, sample)
      local tmp = os.tmpname()
      local c = config.new()
      -- Re-use example from packet filter test.
      config.app(c, "source", PcapReader, "apps/packet_filter/samples/v6.pcap")
      config.app(c, "tap", Tap, {filename=tmp, filter=filter, sample=sample})
      config.app(c, "sink", Sink )

      config.link(c, "source.output -> tap.input")
      config.link(c, "tap.output -> sink.input")
      app.configure(c)
      app.main{done=function () return app.app_table.source.done end}

      local n = 0
      for packet, record in pcap.records(tmp) do n = n + 1 end
      os.remove(tmp)

      app.configure(config.new())

      return n
   end

   assert(run() == 161)
   assert(run("icmp6") == 49)
   assert(run(nil, 2) == 81)
   assert(run("icmp6", 2) == 25)

   print('selftest: ok')
end
