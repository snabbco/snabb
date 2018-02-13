-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Application to connect to a virtio-net driver implementation
--
-- Licensed under the Apache 2.0 license
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Copyright (c) 2015 Virtual Open Systems
--

module(..., package.seeall)

local basic_apps = require("apps.basic.basic_apps")
local pcap       = require("apps.pcap.pcap")
local net_dirver = require("lib.virtio.net_driver")
local main       = require("core.main")

VirtioNet = {}
VirtioNet.__index = VirtioNet

local receive, transmit, nreadable = link.receive, link.transmit, link.nreadable

function VirtioNet:new(args)
   return setmetatable({
      device = assert(net_dirver.VirtioNetDriver:new(args)),
   }, self)
end

function VirtioNet:stop()
   self.device:close()
end

function VirtioNet:push()
   local dev = self.device
   local l = self.input.rx

   dev:recycle_transmit_buffers()

   local to_transmit = math.min(nreadable(l), dev:can_transmit())

   if to_transmit == 0 then return end

   for i=0, to_transmit - 1 do
      dev:transmit(receive(l))
   end
   dev:sync_transmit()
   dev:notify_transmit()
end

function VirtioNet:pull()
   local dev = self.device
   local l = self.output.tx
   if not l then return end
   local to_receive = math.min(engine.pull_npackets, dev:can_receive())

   for i=0, to_receive - 1 do
      transmit(l, dev:receive())
   end
   dev:add_receive_buffers()
end

function selftest()
   local pcidev = os.getenv("SNABB_TEST_VIRTIO_PCIDEV")
   if not pcidev then
      print("SNABB_TEST_VIRTIO_PCIDEV was not set\nTest skipped")
      os.exit(engine.test_skipped_code)
   end
   local input_file = "apps/keyed_ipv6_tunnel/selftest.cap.input"

   engine.configure(config.new())
   local c = config.new()
   config.app(c, 'source', pcap.PcapReader, input_file)
   config.app(c, 'VirtioNet', VirtioNet, {pciaddr=pcidev})
   config.app(c, 'sink', basic_apps.Sink)
   config.link(c, 'source.output -> VirtioNet.rx')
   config.link(c, 'VirtioNet.tx -> sink.input')
   engine.configure(c)
   engine.main({duration = 1, report={showlinks=true, showapps=true}})
end
