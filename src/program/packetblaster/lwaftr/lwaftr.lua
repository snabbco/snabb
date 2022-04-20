-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine    = require("core.app")
local config    = require("core.config")
local timer     = require("core.timer")
local pci       = require("lib.hardware.pci")
local ethernet  = require("lib.protocol.ethernet")
local ipv4      = require("lib.protocol.ipv4")
local ipv6      = require("lib.protocol.ipv6")
local main      = require("core.main")
local S         = require("syscall")
local B4Gen     = require("program.packetblaster.lwaftr.lib").B4Gen
local InetGen   = require("program.packetblaster.lwaftr.lib").InetGen
local Interleave = require("program.packetblaster.lwaftr.lib").Interleave
local Tap       = require("apps.tap.tap").Tap
local vlan      = require("apps.vlan.vlan")
local arp       = require("apps.ipv4.arp")
local ndp       = require("apps.lwaftr.ndp")
local V4V6      = require("apps.lwaftr.V4V6")
local raw       = require("apps.socket.raw")
local pcap      = require("apps.pcap.pcap")
local VhostUser = require("apps.vhost.vhost_user").VhostUser
local lib       = require("core.lib")

local usage = require("program.packetblaster.lwaftr.README_inc")

local long_opts = {
   pci          = "p",    -- PCI address
   tap          = "t",    -- tap interface
   int          = "i",    -- Linux network interface, e.g. eth0
   sock         = "k",    -- socket name for virtio
   duration     = "D",    -- terminate after n seconds
   verbose      = "V",    -- verbose, display stats
   help         = "h",    -- display help text
   size         = "S",    -- frame size list (defaults to IMIX)
   src_mac      = "s",    -- source ethernet address
   dst_mac      = "d",    -- destination ethernet address
   src_mac4     = 1,      -- source ethernet address for IPv4 traffic
   dst_mac4     = 1,      -- destination ethernet address for IPv4 traffic
   src_mac6     = 1,      -- source ethernet address for IPv6 traffic
   dst_mac6     = 1,      -- destination ethernet address for IPv6 traffic
   vlan         = "v",    -- VLAN id
   vlan4        = 1,      -- VLAN id for IPv4 traffic
   vlan6        = 1,      -- VLAN id for IPv6 traffic
   b4           = "b",    -- B4 start IPv6_address,IPv4_address,port
   aftr         = "a",    -- fix AFTR public IPv6_address
   ipv4         = "I",    -- fix public IPv4 address
   count        = "c",    -- how many b4 clients to simulate
   rate         = "r",    -- rate in MPPS (0 => listen only)
   v4only       = "4",    -- generate only public IPv4 traffic
   v6only       = "6",    -- generate only public IPv6 encapsulated traffic
   pcap         = "o"     -- output packet to the pcap file
}

local function dir_exists(path)
  local stat = S.stat(path)
  return stat and stat.isdir
end

function run (args)
   local opt = {}
   local duration
   local c = config.new()

   function opt.D (arg)
      duration = assert(tonumber(arg), "duration is not a number!")
   end

   local verbose
   function opt.V (arg)
      verbose = true
   end

   function opt.h (arg)
      print(usage)
      main.exit(0)
   end

   local sizes = { 64, 64, 64, 64, 64, 64, 64, 594, 594, 594, 1464 }
   function opt.S (arg)
      sizes = {}
      for size in string.gmatch(arg, "%d+") do
         sizes[#sizes + 1] = assert(tonumber(size), "size not a number: "..size)
      end
   end

   local v4_src_mac = "00:00:00:00:00:00"
   function opt.src_mac4 (arg) v4_src_mac = arg end
   local v6_src_mac = "00:00:00:00:00:00"
   function opt.src_mac6 (arg) v6_src_mac = arg end
   function opt.s (arg) opt.src_mac4(arg); opt.src_mac6(arg) end

   local v4_dst_mac = "00:00:00:00:00:00"
   function opt.dst_mac4 (arg) v4_dst_mac = arg end
   local v6_dst_mac = "00:00:00:00:00:00"
   function opt.dst_mac6 (arg) v6_dst_mac = arg end
   function opt.d (arg) opt.dst_mac4(arg); opt.dst_mac6(arg) end

   local b4_ipv6, b4_ipv4, b4_port = "2001:db8::", "10.0.0.0", 1024
   function opt.b (arg) 
      for s in string.gmatch(arg, "[%w.:]+") do
         if string.find(s, ":") then
            b4_ipv6 = s
         elseif string.find(s, '.',1,true) then
            b4_ipv4 = s
         else
            b4_port = assert(tonumber(s), string.format("UDP port %s is not a number!", s))
         end
      end
   end

   local public_ipv4 = "8.8.8.8"
   function opt.I (arg) public_ipv4 = arg end

   local aftr_ipv6 = "2001:db8:ffff::100"
   function opt.a (arg) aftr_ipv6 = arg end

   local count = 1
   function opt.c (arg) 
      count = assert(tonumber(arg), "count is not a number!")
   end

   local rate = 1
   function opt.r (arg) 
      rate = assert(tonumber(arg), "rate is not a number!")
   end

   local target 
   local pciaddr
   function opt.p (arg) 
      pciaddr = arg
      target = pciaddr
   end

   local tap_interface
   function opt.t (arg) 
      tap_interface = arg
      target = tap_interface
   end

   local int_interface
   function opt.i (arg) 
      int_interface = arg
      target = int_interface
   end

   local sock_interface
   function opt.k (arg) 
      sock_interface = arg
      target = sock_interface
   end

   local v4, v6 = true, true

   function opt.v4 () v6 = false end
   opt["4"] = opt.v4

   function opt.v6 () v4 = false end
   opt["6"] = opt.v6

   local v4_vlan
   function opt.vlan4 (arg)
      v4_vlan = assert(tonumber(arg), "vlan is not a number!")
   end
   local v6_vlan
   function opt.vlan6 (arg)
      v6_vlan = assert(tonumber(arg), "vlan is not a number!")
   end
   function opt.v (arg) opt.vlan4(arg); opt.vlan6(arg) end

   local pcap_file, single_pass = nil, false
   function opt.o (arg) 
      pcap_file = arg
      target = pcap_file
      single_pass = true
      rate = 1/0
   end

   args = lib.dogetopt(args, opt, "VD:hS:s:a:d:b:iI:c:r:46p:v:o:t:i:k:", long_opts)

   for _,s in ipairs(sizes) do
      if s < 18 + (v4_vlan and v6_vlan and 4 or 0) + 20 + 8 then
         error("Minimum frame size is 46 bytes (18 ethernet+CRC, 20 IPv4, and 8 UDP)")
      end
   end

   if not target then
      print("either --pci, --tap, --sock, --int or --pcap are required parameters")
      main.exit(1)
   end

   print(string.format("packetblaster lwaftr: Sending %d clients at %.3f MPPS to %s", count, rate, target))
   print()

   if not (v4 or v6) then
      -- Assume that -4 -6 means both instead of neither.
      v4, v6 = true, true
   end

   local v4_input, v4_output, v6_input, v6_output

   local function finish_vlan(input, output, tag)
      if not tag then return input, output end

      -- Add and remove the common vlan tag.
      config.app(c, "untag", vlan.Untagger, {tag=tag})
      config.app(c, "tag", vlan.Tagger, {tag=tag})
      config.link(c, "tag.output -> " .. input)
      config.link(c, input .. " -> untag.input")
      return 'tag.input', 'untag.output'
   end

   local function finish_v4(input, output)
      assert(v4)
      -- Stamp output with the MAC and make an ARP responder.
      local tester_ip = ipv4:pton('1.2.3.4')
      local next_ip = nil -- Assume we have a static dst mac.
      config.app(c, "arp", arp.ARP,
                 { self_ip = tester_ip,
                   self_mac = ethernet:pton(v4_src_mac),
                   next_mac = ethernet:pton(v4_dst_mac),
                   next_ip = next_ip })
      config.link(c, output .. ' -> arp.south')
      config.link(c, 'arp.south -> ' .. input)
      return 'arp.north', 'arp.north'
   end

   local function finish_v6(input, output)
      assert(v6)
      -- Stamp output with the MAC and make an NDP responder.
      local tester_ip = ipv6:pton('2001:DB8::1')
      local next_ip = nil -- Assume we have a static dst mac.
      config.app(c, "ndp", ndp.NDP,
                 { self_ip = tester_ip,
                   self_mac = ethernet:pton(v6_src_mac),
                   next_mac = ethernet:pton(v6_dst_mac),
                   next_ip = next_ip })
      config.link(c, output .. ' -> ndp.south')
      config.link(c, 'ndp.south -> ' .. input)
      return 'ndp.north', 'ndp.north'
   end

   local function split(input, output)
      assert(v4 and v6)
      if v4_vlan ~= v6_vlan then
         -- Split based on vlan.
         config.app(c, "vmux", vlan.VlanMux, {})
         config.link(c, output .. ' -> vmux.trunk')
         config.link(c, 'vmux.trunk -> ' .. input)
         local v4_link = v4_vlan and 'vmux.vlan'..v4_vlan or 'vmux.native'
         v4_input, v4_output = finish_v4(v4_link, v4_link)
         local v6_link = v6_vlan and 'vmux.vlan'..v6_vlan or 'vmux.native'
         v6_input, v6_output = finish_v6(v6_link, v6_link)
      else
         input, output = finish_vlan(input, output, v4_vlan)
         
         -- Split based on ethertype.
         config.app(c, "mux", V4V6.V4V6, {})
         config.app(c, "join", Interleave, {})
         v4_input, v4_output = finish_v4('join.v4', 'mux.v4')
         v6_input, v6_output = finish_v6('join.v6', 'mux.v6')
         config.link(c, output .. " -> mux.input")
         config.link(c, "join.output -> " .. input)
      end
   end

   local function maybe_split(input, output)
      if v4 and v6 then
         split(input, output)
      elseif v4 then
         input, output = finish_vlan(input, output, v4_vlan)
         v4_input, v4_output = finish_v4(input, output)
      else
         input, output = finish_vlan(input, output, v6_vlan)
         v6_input, v6_output = finish_v6(input, output)
      end
   end

   if tap_interface then
      if dir_exists(("/sys/devices/virtual/net/%s"):format(tap_interface)) then
         config.app(c, "tap", Tap, tap_interface)
      else
         print(string.format("tap interface %s doesn't exist", tap_interface))
         main.exit(1)
      end
      maybe_split("tap.input", "tap.output")
   elseif pciaddr then
      local device_info = pci.device_info(pciaddr)
      if v4_vlan then
         print(string.format("IPv4 vlan set to %d", v4_vlan))
      end
      if v6_vlan then
         print(string.format("IPv6 vlan set to %d", v6_vlan))
      end
      if not device_info then
         fatal(("Couldn't find device info for PCI or tap device %s"):format(pciaddr))
      end
      if v4 and v6 then
         if v4_vlan == v6_vlan and v4_src_mac == v6_src_mac then
            config.app(c, "nic", require(device_info.driver).driver,
                       {pciaddr = pciaddr, vmdq = true, macaddr = v4_src_mac,
                        mtu = 9500, vlan = v4_vlan})
            maybe_split("nic."..device_info.rx, "nic."..device_info.tx)
         else
            config.app(c, "v4nic", require(device_info.driver).driver,
                       {pciaddr = pciaddr, vmdq = true, macaddr = v4_src_mac,
                        mtu = 9500, vlan = v4_vlan})
            v4_input, v4_output = finish_v4("v4nic."..device_info.rx,
                                            "v4nic."..device_info.tx)
            config.app(c, "v6nic", require(device_info.driver).driver,
                       {pciaddr = pciaddr, vmdq = true, macaddr = v6_src_mac,
                        mtu = 9500, vlan = v6_vlan})
            v6_input, v6_output = finish_v6("v6nic."..device_info.rx,
                                            "v6nic."..device_info.tx)
         end
      elseif v4 then
         config.app(c, "nic", require(device_info.driver).driver,
                    {pciaddr = pciaddr, vmdq = true, macaddr = v4_src_mac,
                     mtu = 9500, vlan = v4_vlan})
         v4_input, v4_output = finish_v4("nic."..device_info.rx,
                                         "nic."..device_info.tx)
      else
         config.app(c, "nic", require(device_info.driver).driver,
                    {pciaddr = pciaddr, vmdq = true, macaddr = v6_src_mac,
                     mtu = 9500, vlan = v6_vlan})
         v6_input, v6_output = finish_v6("nic."..device_info.rx,
                                         "nic."..device_info.tx)
      end
   elseif int_interface then
      config.app(c, "int", raw.RawSocket, int_interface)
      maybe_split("int.rx", "int.tx")
   elseif sock_interface then
      config.app(c, "virtio", VhostUser, { socket_path=sock_interface } )
      maybe_split("virtio.rx", "virtio.tx")
   else
      config.app(c, "pcap", pcap.PcapWriter, pcap_file)
      maybe_split("pcap.input", "pcap.output")
   end

   if v4 then
      print()
      print(string.format("IPv4: %s:12345 > %s:%d", public_ipv4, b4_ipv4, b4_port))
      print("      destination IPv4 and Port adjusted per client")
      print("IPv4 frame sizes: " .. table.concat(sizes,","))
      local rate = v6 and rate/2 or rate
      config.app(c, "inetgen", InetGen, {
         sizes = sizes, rate = rate, count = count, single_pass = single_pass,
         b4_ipv4 = b4_ipv4, b4_port = b4_port, public_ipv4 = public_ipv4,
         frame_overhead = v4_vlan and 4 or 0})
      if v6_output then
         config.link(c, v6_output .. " -> inetgen.input")
      end
      config.link(c, "inetgen.output -> " .. v4_input)
   end
   if v6 then
      print()
      print(string.format("IPv6: %s > %s: %s:%d > %s:12345", b4_ipv6, aftr_ipv6, b4_ipv4, b4_port, public_ipv4))
      print("      source IPv6 and source IPv4/Port adjusted per client")
      local sizes_ipv6 = {}
      for i,size in ipairs(sizes) do sizes_ipv6[i] = size + 40 end
      print("IPv6 frame sizes: " .. table.concat(sizes_ipv6,","))
      local rate = v4 and rate/2 or rate
      config.app(c, "b4gen", B4Gen, {
         sizes = sizes, rate = rate, count = count, single_pass = single_pass,
         b4_ipv6 = b4_ipv6, aftr_ipv6 = aftr_ipv6,
         b4_ipv4 = b4_ipv4, b4_port = b4_port, public_ipv4 = public_ipv4,
         frame_overhead = v6_vlan and 4 or 0})
      if v4_output then
         config.link(c, v4_output .. " -> b4gen.input")
      end
      config.link(c, "b4gen.output -> " .. v6_input)
   end

   engine.busywait = true
   engine.configure(c)

   if verbose then
      print ("enabling verbose")
      local fn = function ()
         print("Transmissions (last 1 sec):")
         engine.report_apps()
      end
      local t = timer.new("report", fn, 1e9, 'repeating')
      timer.activate(t)
   end

   local done
   if duration then
      done = lib.timeout(duration)
   else
      local b4gen = engine.app_table.b4gen
      local inetgen = engine.app_table.inetgen
      print (b4gen, inetgen)
      function done()
         return ((not b4gen) or b4gen:done()) and ((not inetgen) or inetgen:done())
      end
   end

   engine.main({done=done})
end
