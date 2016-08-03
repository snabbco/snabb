-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local app = require("core.app")
local link = require("core.link")
local lib = require("core.lib")
local packet = require("core.packet")
local config = require("core.config")
local counter = require("core.counter")
local conntrack = require("apps.packet_filter.conntrack")
local C = require("ffi").C

local pf = require("pf")        -- pflua

PcapFilter = {}

-- PcapFilter is an app that drops all packets that don't match a
-- specified filter expression.
--
-- Optionally, connections can be statefully tracked, so that if one
-- packet for a TCP/UDP session is accepted then future packets
-- matching this session are also accepted.
--
-- conf:
--   filter      = string expression specifying which packets to accept
--                 syntax: http://www.tcpdump.org/manpages/pcap-filter.7.html
--   state_table = optional string name to use for stateful-tracking table
function PcapFilter:new (conf)
   assert(conf.filter, "PcapFilter conf.filter parameter missing")

   local o = {
      -- XXX Investigate the latency impact of filter compilation.
      accept_fn = pf.compile_filter(conf.filter),
      state_table = conf.state_table or false,
      shm = { rxerrors = {counter}, sessions_established = {counter} }
   }
   if conf.state_table then conntrack.define(conf.state_table) end
   return setmetatable(o, { __index = PcapFilter })
end

function PcapFilter:push ()
   local i = assert(self.input.input or self.input.rx, "input port not found")
   local o = assert(self.output.output or self.output.tx, "output port not found")

   while not link.empty(i) do
      local p = link.receive(i)
      local spec = self.state_table and conntrack.spec(p.data)

      if spec and spec:check(self.state_table) then
         link.transmit(o, p)
      elseif self.accept_fn(p.data, p.length) then
         if spec then
            spec:track(self.state_table)
            counter.add(self.shm.sessions_established)
         end
         link.transmit(o, p)
      else
         packet.free(p)
         counter.add(self.shm.rxerrors)
      end
   end
end

-- Testing

local pcap = require("apps.pcap.pcap")
local basic_apps = require("apps.basic.basic_apps")

-- This is a simple blind regression test to detect unexpected changes
-- in filtering behavior.
--
-- The PcapFilter app is glue. Instead of having major unit tests of
-- its own it depends on separate testing of pflua and conntrack.
function selftest ()
   print("selftest: pcap_filter")
   selftest_run(false, 3.726, 0.0009)
   selftest_run(true,  7.453, 0.001)
   print("selftest: ok")
end

-- Run a selftest in stateful or non-stateful mode and expect a
-- specific rate of acceptance from the test trace file.
function selftest_run (stateful, expected, tolerance)
   app.configure(config.new())
   conntrack.clear()
   local pcap_filter = require("apps.packet_filter.pcap_filter")
   local v6_rules =
      [[
         (icmp6 and
          src net 3ffe:501:0:1001::2/128 and
          dst net 3ffe:507:0:1:200:86ff:fe05:8000/116)
         or
         (ip6 and udp and
          src net 3ffe:500::/28 and
          dst net 3ffe:0501:4819::/64 and
          src portrange 2397-2399 and
          dst port 53)
      ]]

   local c = config.new()
   local state_table = stateful and "selftest"
   config.app(c, "source", pcap.PcapReader, "apps/packet_filter/samples/v6.pcap")
   config.app(c, "repeater", basic_apps.Repeater )
   config.app(c,"pcap_filter", pcap_filter.PcapFilter,
              {filter=v6_rules, state_table = state_table})
   config.app(c, "sink", basic_apps.Sink )

   config.link(c, "source.output -> repeater.input")
   config.link(c, "repeater.output -> pcap_filter.input")
   config.link(c, "pcap_filter.output -> sink.input")
   app.configure(c)

   print(("Run for 1 second (stateful = %s)..."):format(stateful))

   local deadline = lib.timer(1e9)
   repeat app.breathe() until deadline()

   app.report({showlinks=true})
   local sent     = link.stats(app.app_table.pcap_filter.input.input).rxpackets
   local accepted = link.stats(app.app_table.pcap_filter.output.output).txpackets
   local acceptrate = accepted * 100 / sent
   if acceptrate >= expected and acceptrate <= expected+tolerance then
      print(("ok: accepted %.4f%% of inputs (within tolerance)"):format(acceptrate))
   else
      print(("error: accepted %.4f%% (expected %.3f%% +/- %.5f)"):format(
            acceptrate, expected, tolerance))
      error("selftest failed")
   end
end

