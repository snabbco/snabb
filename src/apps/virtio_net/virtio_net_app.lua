module(..., package.seeall)

local basic_apps = require("apps.basic.basic_apps")
local pcap       = require("apps.pcap.pcap")
local virtio_dev = require("apps.virtio_net.virtio_net_dev")
local main       = require("core.main")

local virtio_net = {}
virtio_net.__index = virtio_net

function virtio_net:new(args)
   return setmetatable({
      device = assert(virtio_dev.VGdev:new(args)),
   }, self)
end

function virtio_net:stop()
   self.device:close()
end

function virtio_net:push()
   local dev = self.device
   local l = self.input.rx
   if not dev or not l then return end

   while not link.empty(l) and dev:can_transmit() do
      dev:transmit(link.receive(l))
   end
   dev:sync_transmit()
end

function virtio_net:pull()
   local dev = self.device
   local l = self.output.tx
   if not dev or not l then return end

   dev:sync_receive()
   while not link.full(l) and dev:can_receive() do
      link.transmit(l, dev:receive())
   end
   self:add_receive_buffers()
end

function virtio_net:add_receive_buffers()
   local dev = self.device
   while dev:can_add_receive_buffer() do
      dev:add_receive_buffer(packet.allocate())
   end
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
   config.app(c, 'virtio_net', virtio_net, {pciaddr=pcidev})
   config.app(c, 'sink', basic_apps.Sink)
   config.link(c, 'source.output -> virtio_net.rx')
   config.link(c, 'virtio_net.tx -> sink.input')
   engine.configure(c)
   engine.main({duration = 1, report={showlinks=true, showapps=true}})
end
