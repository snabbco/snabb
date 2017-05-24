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
local lib = require("core.lib")
local band = bit.band

local t = S.types.t

Tap = { }

local function _mtu (sock, ifr)
   local ok, err = sock:ioctl("SIOCGIFMTU", ifr)
   if not ok then
      error("Error getting MTU for tap device "..ifr.name
               ..": "..tostring(err))
   end
   return ifr.ivalue
end

local function _status (sock, ifr)
   local ok, err = sock:ioctl("SIOCGIFFLAGS", ifr)
   if not ok then
      error("Error getting flags for tap device "..ifr.name
               ..": ".. tostring(err))
   end
   if band(ifr.flags, const.IFF.UP) ~= 0 then
      return 1 -- up
   else
      return 2 -- down
   end
end

local macaddr_t = ffi.typeof[[
   union {
      uint64_t bits;
      uint8_t bytes[6];
   }
]]
local function _macaddr (sock, ifr)
   local ok, err = sock:ioctl("SIOCGIFHWADDR", ifr)
   if not ok then
      error("Error getting MAC address for tap device "
               ..ifr.name..": ".. tostring(err))
   end
   local sa = ifr.hwaddr
   if sa.sa_family ~= const.ARPHRD.ETHER then
      error("Tap interface "..ifr.name
               .." is not of type ethernet "..sa.sa_family)
   else
      return ffi.cast(ffi.typeof("$*", macaddr_t), sa.sa_data).bits
   end
end

function Tap:new (conf)
   local name, mtu, mtu2
   -- Backwards compatibility
   if type(conf) == "string" then
      name = conf
   elseif type(conf) == "table" then
      name = conf.name
      -- MTU handling
      --
      -- For a regular networking device, we use the convention that
      -- the MTU includes the Ethernet header including any VLAN tags.
      -- This value is passed to us in the "mtu" configuration
      -- variable.  However, the MTU of a TAP device does not include
      -- any part of the Ethernet header.  Since the device doesn't
      -- know whether there are any VLAN tags used on top of it, this
      -- driver cannot figure out the proper MTU from that value
      -- alone.  For that reason, another value is passed to the
      -- driver in the variable "mtu2", which excludes all L2 headers.
      -- Like "mtu", this value originates from the user-supplied
      -- configuration and assumes knowledge of the L2 structure of
      -- the TAP device.
      --
      -- Contrary to a physical device, whose MTU is controlled solely
      -- by the driver, the MTU of a TAP device is controlled by the
      -- external process that set up the device.  Hence, it would be
      -- unexpected if the MTU were changed here.  Therefore, we
      -- merely check whether the externally configured MTU matches
      -- the one supplied to us by the Snabb process.  An error is
      -- thrown in case of a mismatch to avoid MTU blackholes within
      -- the Snabb app network.
      --
      -- Both values must be supplied.  "mtu2" is used for checking
      -- but mtu is stored as the actual MTU in the driver stats for
      -- consistency with regular devices.
      mtu = conf.mtu
      mtu2 = conf.mtu2
      assert(mtu and mtu2, "missing MTU and/or MTU2 for tap interface "
                ..(name and name or "<unknown>"))
   end
   assert(name, "missing tap interface name")

   local fd, err = S.open("/dev/net/tun", "rdwr, nonblock");
   assert(fd, "Error opening /dev/net/tun: " .. tostring(err))
   local ifr = t.ifreq()
   ifr.flags = "tap, no_pi"
   ifr.name = name
   local ok, err = fd:ioctl("TUNSETIFF", ifr)
   if not ok then
      fd:close()
      error("ioctl(TUNSETIFF) failed on /dev/net/tun: " .. tostring(err))
   end

   -- A dummy socket to perform SIOC{G,S}IF* ioctl() calls
   local sock, err = S.socket(const.AF.INET, const.SOCK.DGRAM, 0)
   if not sock then
      fd:close()
      error("Error creating query socket for tap device: " .. tostring(err))
   end

   local mtu_tap = _mtu(sock, ifr)
   if mtu2 then
      assert(mtu2 == mtu_tap, "MTU mismatch on "..name
                ..": required "..mtu..", configured "..mtu_tap)
   else
      -- Old-style configuration without MTU: use the MTU from the TAP
      -- device in the stats table.  This value is inconsistent with
      -- that of other devices, because it doesn't include the L2
      -- headers.
      mtu = mtu_tap
   end

   return setmetatable({fd = fd,
                        sock = sock,
                        ifr = ifr,
                        name = name,
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
                                mtu       = {counter, mtu},
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
      -- errno == EAGAIN indicates that the read would of blocked as there is no
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
      -- The write might of blocked so don't dequeue the packet from the link
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
   engine.main({duration = 0.01, report = {showapps=true,showlinks=true}})
   assert(#engine.app_table.match:errors() == 0)
end
