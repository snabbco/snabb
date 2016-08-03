-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local S = require("syscall")
local link = require("core.link")
local packet = require("core.packet")
local counter = require("core.counter")
local ethernet = require("lib.protocol.ethernet")
local ffi = require("ffi")
local C = ffi.C
local const = require("syscall.linux.constants")
local os = require("os")

local t = S.types.t

Tap = { }

function Tap:new (name)
   assert(name, "missing tap interface name")

   local sock, err = S.open("/dev/net/tun", "rdwr, nonblock");
   assert(sock, "Error opening /dev/net/tun: " .. tostring(err))
   local ifr = t.ifreq()
   ifr.flags = "tap, no_pi"
   ifr.name = name
   local ok, err = sock:ioctl("TUNSETIFF", ifr)
   if not ok then
      sock:close()
      error("Error opening /dev/net/tun: " .. tostring(err))
   end
   return setmetatable({sock = sock,
                        name = name,
                        shm = { rxbytes   = {counter},
                                rxpackets = {counter},
                                rxmcast   = {counter},
                                rxbcast   = {counter},
                                txbytes   = {counter},
                                txpackets = {counter},
                                txmcast   = {counter},
                                txbcast   = {counter} }},
                       {__index = Tap})
end

function Tap:pull ()
   local l = self.output.output
   if l == nil then return end
   for i=1,engine.pull_npackets do
      local p = packet.allocate()
      local len, err = S.read(self.sock, p.data, C.PACKET_PAYLOAD_SIZE)
      -- errno == EAGAIN indicates that the read would of blocked as there is no
      -- packet waiting. It is not a failure.
      if not len and err.errno == const.E.AGAIN then
         packet.free(p)
         return
      end
      if not len then
         packet.free(p)
         error("Failed read on " .. self.name .. ": " .. tostring(err))
      end
      p.length = len
      link.transmit(l, p)
      counter.add(self.shm.rxbytes, len)
      counter.add(self.shm.rxpackets)
      if ethernet:is_mcast(p.data) then
         counter.add(self.shm.rxmcast)
      end
      if ethernet:is_bcast(p.data) then
         counter.add(self.shm.rxbcast)
      end
   end
end

function Tap:push ()
   local l = self.input.input
   while not link.empty(l) do
      -- The socket write might of blocked so don't dequeue the packet from the link
      -- until the write has completed.
      local p = link.front(l)
      local len, err = S.write(self.sock, p.data, p.length)
      -- errno == EAGAIN indicates that the write would of blocked
      if not len and err.errno ~= const.E.AGAIN or len and len ~= p.length then
         error("Failed write on " .. self.name .. tostring(err))
      end
      if len ~= p.length and err.errno == const.E.AGAIN then
         return
      end
      counter.add(self.shm.txbytes, len)
      counter.add(self.shm.txpackets)
      if ethernet:is_mcast(p.data) then
         counter.add(self.shm.txmcast)
      end
      if ethernet:is_bcast(p.data) then
         counter.add(self.shm.txbcast)
      end
      -- The write completed so dequeue it from the link and free the packet
      link.receive(l)
      packet.free(p)
   end
end

function Tap:stop()
   self.sock:close()
end

function selftest()
   -- tapsrc and tapdst are bridged together in linux. Packets are sent out of tapsrc and they are expected
   -- to arrive back on tapdst.

   -- The linux bridge does mac address learning so some care must be taken with the preparation of selftest.cap
   -- A mac address should appear only as the source address or destination address

   -- This test should only be run from inside apps/tap/selftest.sh
   if not os.getenv("SNABB_TAPTEST") then os.exit(engine.test_skipped_code) end
   local Synth = require("apps.test.synth").Synth
   local Match = require("apps.test.match").Match
   local c = config.new()
   config.app(c, "tap_in", Tap, "tapsrc")
   config.app(c, "tap_out", Tap, "tapdst")
   config.app(c, "match", Match, {fuzzy=true,modest=true})
   config.app(c, "comparator", Synth, {dst="00:50:56:fd:19:ca",
                                       src="00:0c:29:3e:ca:7d"})
   config.app(c, "source", Synth, {dst="00:50:56:fd:19:ca",
                                   src="00:0c:29:3e:ca:7d"})
   config.link(c, "comparator.output->match.comparator")
   config.link(c, "source.output->tap_in.input")
   config.link(c, "tap_out.output->match.rx")
   engine.configure(c)
   engine.main({duration = 0.01, report = {showapps=true,showlinks=true}})
   assert(#engine.app_table.match:errors() == 0)
end
