-- Test suite for the Mellanox ConnectX driver.
-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local connectx = require("apps.mellanox.connectx")
local counter = require("core.counter")
local lib = require("core.lib")

-- Test scenarios:
--   unicast-multiqueue
--     number of queues

-- Test sending traffic between two directly attached network interfaces.
-- 
--   pci0, pci1: device PCI addresses
--   npackets:   number of packets to transfer (lower bound)
--   ncores:     number of CPU cores per network interface
--   minlen:     minimum packet length (excl. ethernet FCS)
--   maxlen:     maximum packet length
--   minburst:   minimum burst size (packets) sent to the driver
--   maxburst:   maximum burst size
--   macs:       number of unique mac addresses
--   vlans:      number of unique VLAN IDs
--   rss:        number of RSS hash buckets.
-- 
-- Hardware queue count will be macs*vlans*rss on each interface.
function switch (pci0, pci1, npackets, ncores, minlen, maxlen, minburst, maxburst, macs, vlans, rss)
   print("selftest: connectx_test switch")
   assert(ncores == 1, "multicore not yet handled")
   -- Create queue definitions
   local queues = {}
   for vlan = 1, vlans do
      for mac = 1, macs do
         for q = 1, rss do
            local id = ("vlan%d.mac%d.rss%d"):format(vlan, mac, q)
            queues[#queues+1] = {id=id, vlan=vlan, mac="00:00:00:00:00:"..bit.tohex(mac, 2)}
         end
      end
   end
   -- Instantiate app network
   local nic0 = connectx.ConnectX:new({pciaddress=pci0, queues=queues})
   local nic1 = connectx.ConnectX:new({pciaddress=pci1, queues=queues})
   local io0 = {}               -- io apps on nic0
   local io1 = {}               -- io apps on nic1
   print(("creating %d queues per device..."):format(#queues))
   for _, queue in ipairs(queues) do
      local function ioapp (pci, queue)
         local a = connectx.IO:new({pciaddress=pci, queue=queue.id})
         a.input  = { input  = link.new(("input-%s-%s" ):format(pci, queue.id)) }
         a.output = { output = link.new(("output-%s-%s"):format(pci, queue.id)) }
         return a
      end
      io0[queue.id] = ioapp(pci0, queue)
      io1[queue.id] = ioapp(pci1, queue)
   end
   -- Create diverse packet payload templates
   print("creating payloads...")
   local payload = {}
   local npayloads = 1000
   for i = 1, npayloads do
      local p = packet.allocate()
      payload[i] = p
      p.length = between(minlen, maxlen)
      ffi.fill(p.data, p.length, 0)

      -- MAC destination
      local r = math.random()
      if     r < 0.05 then          -- 5% of packets are broadcast
         ffi.fill(p.data, 6, 0xFF)
      elseif r < 0.10 then          -- 5% of packets are multicast
         p.data[0], p.data[1] = 0x33, 0x33 -- "locally administered" multicast
      elseif r < 0.20 then          -- 10% are unicast to random destinations
         for i = 1, 5 do p.data[i] = math.random(256) - 1 end
      else                          -- rest are unicast to known mac
         p.data[5] = between(1, macs)
      end
      
      -- MAC source
      for i = 7, 11 do p.data[i] = math.random(256) - 1 end

      -- 802.1Q
      p.data[12] = 0x81
      p.data[15] = between(1, vlans) -- vlan id can be out of expected range
      p.data[16] = 0x08 -- ipv4

      local ip_ofs = 18

      -- IPv4
      local ip = require("lib.protocol.ipv4"):new{
         src = lib.random_bytes(4),
         dst = lib.random_bytes(4),
         ttl = 64
      }
      if r < 0.50 then              -- 50% of packets are UDP (have L4 header)
         ip:protocol(17) -- UDP
      else                          -- rest have random payloads
         ip:protocol(253)
      end
      ip:copy(p.data+ip_ofs, 'relocate')
      ip:total_length(p.length-ip_ofs)
      ip:checksum()

      if ip:protocol() == 17 then
         -- UDP
         local udp = require("lib.protocol.udp"):new{
            src_port = math.random(30000),
            dst_port = math.random(30000)
         }
         udp:copy(p.data+ip_ofs+ip:sizeof(), 'relocate')
         udp:length(p.length-(ip_ofs+ip:sizeof()))

         -- Random payload
         for i = ip_ofs+ip:sizeof()+udp:sizeof(), p.length-1 do
            p.data[i] = math.random(256) - 1
         end

         -- UDP checksum
         udp:checksum(p.data, p.length-(ip_ofs+ip:sizeof()+udp:sizeof()), ip)
      
      else
         -- Random payload
         for i = ip_ofs+ip:sizeof(), p.length-1 do
            p.data[i] = math.random(256) - 1
         end
      end

      --print(lib.hexdump(ffi.string(p.data, 32)))
   end
   -- Wait for linkup on both ports
   print("waiting for linkup...")
   while not (nic0.hca:linkup() and nic1.hca:linkup()) do C.usleep(0.25e6) end
   -- Send packets
   print("sending packets...")

   local function dump (pci, id, app)
      -- Dump received packets
      while not link.empty(app.output.output) do
         local p = link.receive(app.output.output)
         --print(("recv %s %4d %s: %s"):format(pci, p.length, id, lib.hexdump(ffi.string(p.data, 32))))
         packet.free(p)
      end
   end

   local start = engine.now()
   local remaining = npackets
   engine.vmprofile_enabled = true
   engine.setvmprofile("connectx")
   while remaining > 0 do
      -- Send packets
      for id, _ in pairs(io0) do
         for i = 1, between(minburst, maxburst) do
            if remaining > 0 then
               local p = payload[between(1, npayloads)]
               --print(("send(%4d): %s"):format(p.length, lib.hexdump(ffi.string(p.data, 32))))
               link.transmit(io0[id].input.input, packet.clone(p))
               link.transmit(io1[id].input.input, packet.clone(p))
               remaining = remaining - 1
            end
         end
      end
      -- Simulate breathing
      --C.usleep(100)
      for id, app in pairs(io0) do app:pull() app:push() dump(pci0, id, app) end
      for id, app in pairs(io1) do app:pull() app:push() dump(pci1, id, app) end
      -- Simulate breathing
   end
   engine.setvmprofile("engine")
   -- Receive any last packets
   C.usleep(100)
   for i = 1, 10 do
      for id, app in pairs(io0) do app:pull() app:push() dump(pci0, id, app) end
      for id, app in pairs(io1) do app:pull() app:push() dump(pci1, id, app) end
   end
   local finish = engine.now()
   print("reporting...")
   print(("%-16s  %20s  %20s"):format("hardware counter", pci0, pci1))
   print("----------------  --------------------  --------------------")
   local stat0 = nic0.hca:query_vport_counter()
   local stat1 = nic1.hca:query_vport_counter()
   -- Sort into key order
   local t = {}
   for k in pairs(stat0) do table.insert(t, k) end
   table.sort(t)
   for _, k in pairs(t) do
      print(("%-16s  %20s  %20s"):format(k, lib.comma_value(stat0[k]), lib.comma_value(stat1[k])))
   end

   local received = {[pci0]={}, [pci1]={}}
   print(("@@ %16s; %12s; %12s; %12s; %12s; %12s; %12s; %12s"):format(
         "nic", "link", "txpkt", "txbyte", "txdrop", "rxpkt", "rxbyte", "rxdrop"))
   -- Sort into key order
   local t = {}
   for k in pairs(io0) do table.insert(t, k) end
   table.sort(t)
   for _, id in pairs(t) do
      local function prlink (nic, id, app)
         local function count (cnt) return tonumber(counter.read(cnt)) end
         local stx = app.input.input.stats
         local srx = app.output.output.stats
         print(("@@ %16s; %12s; %12d; %12d; %12d; %12d; %12d; %12d"):format(
               nic, id,
               count(stx.txpackets), count(stx.txbytes), count(stx.txdrop),
               count(srx.txpackets), count(srx.txbytes), count(srx.txdrop)))
         received[nic][#received[nic]+1] = count(srx.txpackets)
      end
      prlink(pci0, id, io0[id])
      prlink(pci1, id, io1[id])
   end
   print(("time: %.1fs - Mpps: %.3f per NIC"):format(finish-start, npackets/1e6/(finish-start)))

   print("hardware counter check")
   assert(stat0.tx_ucast_packets+stat0.tx_mcast_packets+stat0.tx_bcast_packets == npackets, "0: sent too little")
   assert(stat1.tx_ucast_packets+stat1.tx_mcast_packets+stat1.tx_bcast_packets == npackets, "1: sent too little")
   assert(stat0.tx_ucast_packets == stat1.rx_ucast_packets, "0.tx_ucast != 1.rx_ucast")
   assert(stat1.tx_ucast_packets == stat0.rx_ucast_packets, "1.tx_ucast != 0.rx_ucast")
   assert(stat0.tx_mcast_packets*2 == stat1.rx_mcast_packets, "0.tx_mcast*2 != 1.rx_mcast")
   assert(stat1.tx_mcast_packets*2 == stat0.rx_mcast_packets, "1.tx_mcast*2 != 0.rx_mcast")
   assert(stat0.tx_bcast_packets*2 == stat1.rx_bcast_packets, "0.tx_bcast*2 != 1.rx_bcast")
   assert(stat1.tx_bcast_packets*2 == stat0.rx_bcast_packets, "1.tx_bcast*2 != 0.rx_bcast")

   for _, nic in pairs{pci0, pci1} do
      local sum, avg, sd = sum(received[nic]), mean(received[nic]), stdev(received[nic])
      print(("RX check %s   sum=%d avg=%.1f sd=%.1f")
         :format(nic, sum, avg, sd))
      -- expect some slack because we send 10% to random MACs
      assert(sum >= npackets*.8, "received too little")
      -- expect more packets on queues 0 because we send 10% mcast,
      -- but mostly even distribution of packets
      assert(sd / avg < .2, "uneven packet distribution")
   end

   nic0:stop()
   nic1:stop()
   for _, queue in ipairs(queues) do
      io0[queue.id]:stop()
      link.free(io0[queue.id].input.input, ("input-%s-%s" ):format(pci0, queue.id))
      link.free(io0[queue.id].output.output, ("output-%s-%s" ):format(pci0, queue.id))
      io1[queue.id]:stop()
      link.free(io1[queue.id].input.input, ("input-%s-%s" ):format(pci1, queue.id))
      link.free(io1[queue.id].output.output, ("output-%s-%s" ):format(pci1, queue.id))
   end

   print("selftest: done")
end

-- Return a random number between min and max (inclusive.)
function between (min, max)
   if min == max then
      return min
   else
      return min + math.random(max-min+1) - 1
   end
end

function sum (values)
   local sum = 0
   for _, value in ipairs(values) do
      sum = sum + value
   end
   return sum
end

function mean (values)
   return sum(values) / #values
end

function stdev (values)
   local avg = mean(values)
   local var = {}
   for _, value in ipairs(values) do
      var[#var+1] = (value-avg)^2
   end
   return math.sqrt(mean(var))
end

function basic_match (pci0, pci1)
   print("selftest: connectx_test match")
   
   local packet_count = 1001
   local src, dst = "00:00:00:00:00:01", "00:00:00:00:00:02"

   local basic = require("apps.basic.basic_apps")
   local match = require("apps.test.match")
   local npackets = require("apps.test.npackets")
   local synth = require("apps.test.synth")
   local counter = require("core.counter")

   local c = config.new()
   config.app(c, "synth", synth.Synth, {
      sizes={64,67,128,133,192,256,384,512,777,1024},
      src=src,
      dst=dst,
      random_payload=true
   })
   config.app(c, "tee", basic.Tee)
   config.app(c, "match", match.Match)
   config.app(c, "npackets", npackets.Npackets, {npackets=packet_count})
   config.app(c, "nic0", connectx.ConnectX, {
      pciaddress=pci0,
      queues={{id="io0", mac=src}}
   })
   config.app(c, "io0", connectx.IO, {pciaddress=pci0, queue="io0"})
   config.app(c, "nic1", connectx.ConnectX, {
      pciaddress=pci1,
      queues={{id="io1", mac=dst}}
   })
   config.app(c, "io1", connectx.IO, {pciaddress=pci1, queue="io1"})

   config.link(c, "synth.output -> npackets.input")
   config.link(c, "npackets.output -> tee.input")
   config.link(c, "tee.output1 -> io0.input")
   config.link(c, "io1.output -> match.rx")
   config.link(c, "tee.output2 -> match.comparator")

   engine.configure(c)

   engine.main({duration = 1, report = false})
   engine.report_links()
   engine.report_apps()

   local m = engine.app_table['match']
   assert(#m:errors() == 0, "Corrupt packets.")

   engine.configure(config.new())

   print("selftest: done")
end

function selftest ()
   local pci0 = os.getenv("SNABB_PCI_CONNECTX_0")
   local pci1 = os.getenv("SNABB_PCI_CONNECTX_1")
   if not (pci0 and pci1) then
      print("SNABB_PCI_CONNECTX_0 and SNABB_PCI_CONNECTX_1 must be set. Skipping selftest.")
      os.exit(engine.test_skipped_code)
   end
   basic_match(pci0, pci1)
   switch(pci0, pci1, 10e6, 1, 60, 1500, 100, 100, 2, 2, 4)
   switch(pci0, pci1, 10e6, 1, 60, 1500, 100, 100, 1, 2, 8)
   switch(pci0, pci1, 10e6, 1, 60, 1500, 100, 100, 4, 1, 4)
end

