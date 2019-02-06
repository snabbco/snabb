-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local S = require("syscall")
local lib = require("core.lib")
local lwdebug = require("apps.lwaftr.lwdebug")

local ffi = require("ffi")
local C = ffi.C

require("apps.socket.xdp.xdpsock_app_h")

XDPSocket = {}
XDPSocket.__index = XDPSocket

function XDPSocket:new (ifname)
   assert(ifname)

   local ret = C.init_xdp(ifname) 
   if not ret then
      print("Error initializing XDP Socket in "..ifname)
      os.exit(1)
   end

   local o = {
      dev = {
         context = ret,
         can_receive = C.can_receive,
         can_transmit = C.can_transmit,
         receive = C.receive_packet,
         transmit = C.transmit_packet,
      }
   }
   return setmetatable(o, {__index = XDPSocket})
end

function XDPSocket:can_receive ()
   return self.dev.can_receive(self.dev.context)
end

function XDPSocket:receive ()
	local p = packet.allocate()
   local sz = self.dev.receive(self.dev.context, p.data)
   if sz == 0 then return end
   p.length = sz
	return p
end

function XDPSocket:pull ()
   local tx = self.output and self.output.tx
   if not tx then return end
   local limit = engine.pull_npackets
	while limit > 0 do
      local pkt = self:receive()
      if not pkt then break end
      -- lwdebug.print_pkt(pkt)
      link.transmit(tx, pkt)
      limit = limit - 1
	end
end

function XDPSocket:can_transmit()
   return self.dev.can_transmit(self.dev.context)
end

function XDPSocket:transmit (p)
   return self.dev.transmit(self.dev.context, p.data, p.length + 1)
end

function XDPSocket:push ()
   local rx = self.input and self.input.rx
   if not rx then return end
   while not link.empty(rx) do
		if not self:can_transmit() then break end
      local p = link.receive(rx)
		if p.length > 0 then
			self:transmit(p)
		end
		packet.free(p)
   end
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
