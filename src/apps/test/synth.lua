-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local ffi = require("ffi")
local ethernet = require("lib.protocol.ethernet")
local datagram = require("lib.protocol.datagram")
local transmit, receive = link.transmit, link.receive

Synth = {
   config = {
      sizes = {default={64}},
      src = {default='00:00:00:00:00:00'},
      dst = {default='00:00:00:00:00:00'},
      random_payload = { default = false },
      packet_id = { default = false },
   }
}

function Synth:new (conf)
   assert(#conf.sizes >= 1, "Needs at least one size.")
   local packets = {}
   for i, size in ipairs(conf.sizes) do
      local payload_size = size - ethernet:sizeof()
      assert(payload_size >= 0 and payload_size <= 1536,
             "Invalid payload size: "..payload_size)
      local data = ffi.new("char[?]", payload_size)
      if conf.random_payload then
         -- dstmac + srcmac + type
         local off = 6 + 6 + 2
         ffi.fill(data, payload_size)
         ffi.copy(data + off,
            lib.random_bytes(payload_size - off), payload_size - off)
      end

      local dgram = datagram:new(packet.from_pointer(data, payload_size))
      local ether = ethernet:new({ src = ethernet:pton(conf.src),
				   dst = ethernet:pton(conf.dst),
                                   type = payload_size })
      dgram:push(ether)
      packets[i] = dgram:packet()
   end
   return setmetatable({packets=packets}, {__index=Synth})
end

function Synth:pull ()
   for _, o in ipairs(self.output) do
      local n = 0
      while n < engine.pull_npackets do
         for _, p in ipairs(self.packets) do
            local c = packet.clone(p)
            if self.packet_id then
               -- 14 == sizeof(dstmac srcmac type)
               ffi.cast("uint32_t *", clone.data+14)[0] = lib.htonl(self.pktid)
               self.pktid = self.pktid + 1
            end
	    transmit(o, c)
            n = n + 1
	 end
      end
   end
end

function Synth:stop ()
   for _, p in ipairs(self.packets) do
      packet.free(p)
   end
end

function selftest ()
   local pcap = require("apps.pcap.pcap")
   local Match = require("apps.test.match").Match
   local c = config.new()
   config.app(c, "match", Match)
   config.app(c, "reader", pcap.PcapReader, "apps/test/synth.pcap")
   config.app(c, "synth", Synth, { sizes = {32, 64, 128},
				   src = "11:11:11:11:11:11",
				   dst = "22:22:22:22:22:22" })
   config.link(c, "reader.output->match.comparator")
   config.link(c, "synth.output->match.rx")
   engine.configure(c)
   engine.main({ duration = 0.0001, report = {showapps=true,showlinks=true}})
   assert(#engine.app_table.match:errors() == 0)
end
