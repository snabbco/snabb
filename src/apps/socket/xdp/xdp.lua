-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local S = require("syscall")
local lib = require("core.lib")
local lwdebug = require("apps.lwaftr.lwdebug")

local ffi = require("ffi")
local C = ffi.C

local cast = ffi.cast

require("apps.socket.xdp.xdpsock_app_h")

XDPSocket = {}
XDPSocket.__index = XDPSocket

local BATCH_SIZE = 16

function XDPSocket:new (conf)
   if type(conf) == 'string' then
      conf = {
         ifname = assert(conf),
         batch_size = BATCH_SIZE,
      }
   end
   assert(type(conf) == 'table')

   local ret = C.init_xdp(conf.ifname)
   if not ret then
      print("Error initializing XDP Socket in "..conf.ifname)
      os.exit(1)
   end

   local batch_size = conf.batch_size or BATCH_SIZE
   local o = {
      batch_size = batch_size,
      rx_packets = ffi.new("struct packet*[?]", batch_size),
      tx_packets = ffi.new("struct packet*[?]", batch_size),
      dev = {
         context = ret,
         can_receive = C.can_receive,
         can_transmit = C.can_transmit,
         receive = C.receive_packet,
         receive_packets = C.receive_packets,
         transmit = C.transmit_packet,
         transmit_packets = C.transmit_packets,
      }
   }
   for i=0,batch_size-1 do
      o.tx_packets[i] = packet.allocate()
   end
   return setmetatable(o, {__index = XDPSocket})
end

function XDPSocket:can_receive ()
   return self.dev.can_receive(self.dev.context)
end

function XDPSocket:receive ()
	local p = self.tx_packets[0]
   local rcvd = self.dev.receive(self.dev.context, cast("void*", p))
   if rcvd == 0 then return end
	return rcvd
end

function XDPSocket:receive_packets ()
   local rcvd = self.dev.receive_packets(self.dev.context, cast("void**", self.tx_packets), self.batch_size)
   if rcvd == 0 then return end
   return tonumber(rcvd)
end

function XDPSocket:pull ()
   local tx = self.output and self.output.tx
   if not tx then return end
   local limit = engine.pull_npackets
	while limit > 0 do
      local rcvd = self:receive_packets()
      if not rcvd then break end
      for i=0,rcvd-1 do
         -- lwdebug.print_pkt(self.tx_packets[i])
         link.transmit(tx, packet.clone(self.tx_packets[i]))
      end
      limit = limit - rcvd
	end
end

function XDPSocket:can_transmit()
   return self.dev.can_transmit(self.dev.context)
end

function XDPSocket:transmit (p)
   self.dev.transmit(self.dev.context, cast("void*", p))
end

function XDPSocket:transmit_packets (packets, nmemb)
   self.dev.transmit_packets(self.dev.context, cast("void**", packets), nmemb)
end

function XDPSocket:push ()
   local packets = self.rx_packets
   local nmemb = 0
   local function receive (l)
      packets[nmemb] = link.receive(l)
      nmemb = nmemb + 1
   end
   local function free ()
      for i=0,nmemb-1 do
         packet.free(packets[i])
      end
      nmemb = 0
   end
   local function transmit ()
      self:transmit_packets(packets, nmemb)
   end
   local rx = self.input and self.input.rx
   if not rx then return end
   while not link.empty(rx) and self:can_transmit() do
      receive(rx)
      if nmemb == self.batch_size then
         transmit()
         free()
      end
   end
   transmit()
   free()
end

function selftest ()
   print("selftest:")
   local lib = require("core.lib")
   local basic_apps = require("apps.basic.basic_apps")

   local function stats (l)
      local w = function (arg1, arg2)
         io.stdout:write(arg1) print(arg2)
      end
      w("dtime: ", l.stats.dtime)
      w("txbytes: ", l.stats.txbytes)
      w("rxbytes: ", l.stats.rxbytes)
      w("txpackets: ", l.stats.txpackets)
      w("rxpackets: ", l.stats.rxpackets)
      w("txdrop: ", l.stats.txdrop)
   end
   local function test_app_and_links (pkt, if_name)
      local counter = require("core.counter")
      local xdp = XDPSocket:new(if_name)
      xdp.input = {
         rx = link.new("l_input")
      }
      link.transmit(xdp.input.rx, pkt)
      assert(counter.read(xdp.input.rx.stats.txpackets) == 1)
      xdp:push()
      assert(counter.read(xdp.input.rx.stats.rxpackets) == 1)
   end
   local function test_send (pkt, if_name)
      engine.configure(config.new())

      local c = config.new()
      config.app(c, "source", basic_apps.Source)
      config.app(c, "tee", basic_apps.Tee)
      config.app(c, "nic0", XDPSocket, if_name)
      config.app(c, "sink", basic_apps.Sink)
   
      config.link(c, "source.tx -> tee.rx")
      config.link(c, "tee.tx -> nic0.rx")
   
      engine.configure(c)
      engine.app_table.source:set_packet(pkt)
   
      engine.main({duration=0.1, report={showlinks=true}})
   end
   local function test_send_and_receive (pkt, if_name0, if_name1)
      engine.configure(config.new())

      local c = config.new()
      config.app(c, "source", basic_apps.Source)
      config.app(c, "tee", basic_apps.Tee)
      config.app(c, "nic0", XDPSocket, if_name0)
      config.app(c, "nic1", XDPSocket, if_name1)
      config.app(c, "sink", basic_apps.Sink)
   
      config.link(c, "source.tx -> tee.rx")
      config.link(c, "tee.tx -> nic0.rx")
      config.link(c, "nic1.tx -> sink.rx")
   
      engine.configure(c)
      engine.app_table.source:set_packet(pkt)
   
      engine.main({duration=0.1, report={showlinks=true}})
   end
   local function test_receive (pkt, if_name)
      engine.configure(config.new())

      local c = config.new()
      config.app(c, "nic0", XDPSocket, if_name)
      config.app(c, "sink", basic_apps.Sink)
   
      config.link(c, "nic0.tx -> sink.rx")
   
      engine.configure(c)
   
      engine.main({duration=0.1, report={showlinks=true}})
   end

   local if_name0 = lib.getenv("SNABB_PCI0") or lib.getenv("SNABB_IFNAME0")
   if not if_name0 then
      print("skipped")
      return main.exit(engine.test_skipped_code)
   end

   local pkt = packet.from_string(lib.hexundump([=[
      90 e3 ba ac b9 b4 90 e2 ba ac b9 48 08 00 45 00
      00 34 00 00 00 00 0f 11 d9 40 08 08 08 08 c1 05
      01 64 30 39 04 00 00 20 00 00 00 00 00 00 00 00
      00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
      00 00
	]=], 66))

   test_app_and_links(pkt, if_name0)
   test_send(pkt, if_name0)
   local if_name1 = lib.getenv("SNABB_PCI1") or lib.getenv("SNABB_IFNAME1")
   if if_name1 then
      test_send_and_receive(pkt, if_name0, if_name1)
   end

   print("ok")
end
