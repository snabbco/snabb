-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local S = require("syscall")
local link = require("core.link")
local packet = require("core.packet")
local counter = require("core.counter")
local ethernet = require("lib.protocol.ethernet")
local macaddr = require("lib.macaddress")
local ffi = require("ffi")
local C = ffi.C
local const = require("syscall.linux.constants")
local os = require("os")
local lib = require("core.lib")
local band, bor, bnot = bit.band, bit.bor, bit.bnot

local t = S.types.t

Tap = { }
-- The original version of this driver expected the name of the tap
-- device as only configuration option.  To be backwards compatible,
-- we don't use the automatic arg checking capability of core.config,
-- hence the name _config instead of config for this table.
Tap._config = {
   name = { required = true },
   mtu = { default = 1514 },
   mtu_fixup = { default = true },
   mtu_offset = { default = 14 },
   mtu_set = { default = nil },
}

-- Get or set the MTU of a tap device.  Return the current value.
local function _mtu (sock, ifr, mtu)
   local op = "SIOCGIFMTU"
   if mtu then
      op = "SIOCSIFMTU"
      ifr.ivalue = mtu
   end
   local ok, err = sock:ioctl(op, ifr)
   if not ok then
      error(op.." failed for tap device " .. ifr.name
               .. ": " ..tostring(err))
   end
   return ifr.ivalue
end

-- Get or set the operational status of a tap device.  Return the
-- current status.
local function _status (sock, ifr, status)
   local ok, err = sock:ioctl("SIOCGIFFLAGS", ifr)
   if not ok then
      error("Error getting flags for tap device " .. ifr.name
               .. ": " .. tostring(err))
   end
   if status ~= nil then
      if status == 1 then
         -- up
         ifr.flags = bor(ifr.flags, const.IFF.UP)
      else
         -- down
         ifr.flags = band(ifr.flags, bnot(const.IFF.UP))
      end
      local ok, err = sock:ioctl("SIOCSIFFLAGS", ifr)
      if not ok then
         error("Error setting flags for tap device " .. ifr.name
                  .. ": " .. tostring(err))
      end
   else
      if band(ifr.flags, const.IFF.UP) ~= 0 then
         return 1 -- up
      else
         return 2 -- down
      end
   end
end

-- Get the MAC address of a tap device as a int64_t
local function _macaddr (sock, ifr)
   local ok, err = sock:ioctl("SIOCGIFHWADDR", ifr)
   if not ok then
      error("Error getting MAC address for tap device "
               .. ifr.name ..": " .. tostring(err))
   end
   local sa = ifr.hwaddr
   if sa.sa_family ~= const.ARPHRD.ETHER then
      error("Tap interface " .. ifr.name
               .. " is not of type ethernet: " .. sa.sa_family)
   else
      return macaddr:new(ffi.cast("uint64_t*", sa.sa_data)[0]).bits
   end
end

function Tap:new (conf)
   -- Backwards compatibility
   if type(conf) == "string" then
      conf = { name = conf }
   end
   conf = lib.parse(conf, self._config)

   local ephemeral = not S.stat('/sys/class/net/'..conf.name)
   local fd, err = S.open("/dev/net/tun", "rdwr, nonblock");
   assert(fd, "Error opening /dev/net/tun: " .. tostring(err))
   local ifr = t.ifreq()
   ifr.flags = "tap, no_pi"
   ifr.name = conf.name
   local ok, err = fd:ioctl("TUNSETIFF", ifr)
   if not ok then
      fd:close()
      error("ioctl(TUNSETIFF) failed on /dev/net/tun: " .. tostring(err))
   end

   -- A dummy socket to perform SIOC{G,S}IF* ioctl() calls. Any
   -- PF/type would do.
   local sock, err = S.socket(const.AF.PACKET, const.SOCK.RAW, 0)
   if not sock then
      fd:close()
      error("Error creating ioctl socket for tap device: " .. tostring(err))
   end

   if ephemeral then
      -- Set status to "up"
      _status(sock, ifr, 1)
   end
   local mtu_eff = conf.mtu - (conf.mtu_fixup and conf.mtu_offset) or 0
   local mtu_set = conf.mtu_set
   if mtu_set == nil then
      mtu_set = ephemeral
   end
   if mtu_set then
      _mtu(sock, ifr, mtu_eff)
   else
      local mtu_configured = _mtu(sock, ifr)
      assert(mtu_configured == mtu_eff,
             "Mismatch of IP MTU on tap device " .. conf.name
                .. ": expected " .. mtu_eff .. ", configured "
                .. mtu_configured)
   end

   return setmetatable({fd = fd,
                        sock = sock,
                        ifr = ifr,
                        name = conf.name,
                        status_timer = lib.throttle(0.001),
                        pkt = packet.allocate(),
                        shm = { rxbytes   = {counter},
                                rxpackets = {counter},
                                rxmcast   = {counter},
                                rxbcast   = {counter},
                                txbytes   = {counter},
                                txpackets = {counter},
                                txmcast   = {counter},
                                txbcast   = {counter},
                                type      = {counter, 0x1001}, -- propVirtual
                                status    = {counter, _status(sock, ifr)},
                                mtu       = {counter, conf.mtu},
                                speed     = {counter, 0},
                                macaddr   = {counter, _macaddr(sock, ifr)} }},
      {__index = Tap})
end

function Tap:status()
   counter.set(self.shm.status, _status(self.sock, self.ifr))
end

function Tap:pull ()
   local l = self.output.output
   if l == nil then return end
   if self.status_timer() then
      self:status()
   end
   for i=1,engine.pull_npackets do
      local len, err = S.read(self.fd, self.pkt.data, C.PACKET_PAYLOAD_SIZE)
      -- errno == EAGAIN indicates that the read would have blocked as there is no
      -- packet waiting. It is not a failure.
      if not len and err.errno == const.E.AGAIN then
         return
      end
      if not len then
         error("Failed read on " .. self.name .. ": " .. tostring(err))
      end
      self.pkt.length = len
      link.transmit(l, self.pkt)
      counter.add(self.shm.rxbytes, len)
      counter.add(self.shm.rxpackets)
      if ethernet:is_mcast(self.pkt.data) then
         counter.add(self.shm.rxmcast)
      end
      if ethernet:is_bcast(self.pkt.data) then
         counter.add(self.shm.rxbcast)
      end
      self.pkt = packet.allocate()
   end
end

function Tap:push ()
   local l = self.input.input
   while not link.empty(l) do
      -- The write might have blocked so don't dequeue the packet from the link
      -- until the write has completed.
      local p = link.front(l)
      local len, err = S.write(self.fd, p.data, p.length)
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
   self.fd:close()
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
   engine.main({duration = 0.05, report = {showapps=true,showlinks=true}})
   assert(#engine.app_table.match:errors() == 0)
end
