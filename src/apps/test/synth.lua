module(...,package.seeall)

local ffi = require("ffi")
local ethernet = require("lib.protocol.ethernet")
local datagram = require("lib.protocol.datagram")
local transmit, receive = link.transmit, link.receive

Synth = {}

function Synth:new (arg)
   local conf = arg and config.parse_app_arg(arg) or {}
   conf.size = conf.size or 64
   conf.src = conf.src or '00:00:00:00:00:00'
   conf.dst = conf.dst or '00:00:00:00:00:00'
   local ether = ethernet:new({ src = ethernet:pton(conf.src), 
				dst = ethernet:pton(conf.dst) })
   local payload_size = conf.size - ethernet:sizeof()
   local data = ffi.new("char[?]", payload_size)
   local dgram = datagram:new(packet.from_pointer(data, payload_size))   
   dgram:push(ether)
   return setmetatable({packet=dgram:packet()}, {__index=Synth})
end

function Synth:pull ()
   for _, o in ipairs(self.output) do
      for i = 1, link.nwritable(o) do
         transmit(o, packet.clone(self.packet))
      end
   end
end

function Synth:stop ()
   packet.free(self.packet)
end

function selftest ()
   local pcap = require("apps.pcap.pcap")
   local c = config.new()
   config.app(c, "synth", Synth, { size = 128, 
				   src = "11:11:11:11:11:11",
				   dst = "22:22:22:22:22:22" })
   config.app(c, "writer", pcap.PcapWriter, "apps/test/synth.pcap.output")
   config.link(c, "synth.output->writer.input")
   engine.configure(c)
   engine.main( {duration = 0.00000001, -- hack: one breath.
		 report   = { showlinks = true } } )

   if io.open("apps/test/synth.pcap"):read('*a') ~=
      io.open("apps/test/synth.pcap.output"):read('*a')
   then
      error("synth.pcap and synth.pcap.output differ.")
   end
end
