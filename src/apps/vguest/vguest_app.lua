
module(..., package.seeall)
local pci       = require("lib.hardware.pci")
local virtio_dev = require("apps.vguest.vguest_dev")


local VGuest = {}
VGuest.__index = VGuest


function VGuest:new(args)
   return setmetatable({
      device = assert(virtio_dev.VGdev:new(args)),
   }, self)
end


function VGuest:stop()
   self.device:close()
end


function VGuest:push()
   local dev = self.device
   local l = self.input.rx
   if not dev or not l then return end

   while not l:empty() and dev:can_transmit() do
--       print('>')
      dev:transmit(l:receive())
   end
   dev:sync_transmit()
end


function VGuest:pull()
--    print ("VGuest:pull()")
   local dev = self.device
   local l = self.output.tx
   if not dev or not l then return end

   dev:sync_receive()
   while not l:full() and dev:can_receive() do
      l:transmit(dev:receive())
   end
   self:add_receive_buffers()
end


function VGuest:add_receive_buffers()
   local dev = self.device
   while dev:can_add_receive_buffer() do
      dev:add_receive_buffer(packet.allocate())
   end
end


local pcap = require("apps.pcap.pcap")
local basic_apps = require("apps.basic.basic_apps")


function selftest()
   local pcidev = '0000:00:07.0'       -- os.getenv("SNABB_TEST_VIRTIO_PCIDEV")
   local input_file = "apps/keyed_ipv6_tunnel/selftest.cap.input"
--    local vg = VGuest:new({pciaddr=pcidev})

   engine.configure(config.new())
   local c = config.new()
   config.app(c, 'source', pcap.PcapReader, input_file)
   config.app(c, 'vguest', VGuest, {pciaddr=pcidev})
   config.app(c, 'sink', basic_apps.Sink)
   config.link(c, 'source.output -> vguest.rx')
   config.link(c, 'vguest.tx -> sink.input')
   engine.configure(c)
   engine.main({duration = 1, report={showlinks=true, showapps=true}})

end
