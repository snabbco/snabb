-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine    = require("core.app")
local config    = require("core.config")
local timer     = require("core.timer")
local pci       = require("lib.hardware.pci")
local main      = require("core.main")
local S         = require("syscall")
local Lwaftrgen = require("apps.test.lwaftr").Lwaftrgen
local Tap       = require("apps.tap.tap").Tap
local raw       = require("apps.socket.raw")
local pcap      = require("apps.pcap.pcap")
local VhostUser = require("apps.vhost.vhost_user").VhostUser
local lib       = require("core.lib")
local ffi       = require("ffi")

local usage = require("program.packetblaster.lwaftr.README_inc")

local long_opts = {
   pci          = "p",    -- PCI address
   tap          = "t",    -- tap interface
   int          = "i",    -- Linux network interface, e.g. eth0
   sock         = "k",    -- socket name for virtio
   duration     = "D",    -- terminate after n seconds
   verbose      = "V",    -- verbose, display stats
   help         = "h",    -- display help text
   size         = "S",    -- packet size list (defaults to IMIX)
   src_mac      = "s",    -- source ethernet address
   dst_mac      = "d",    -- destination ethernet address
   vlan         = "v",    -- VLAN id
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

   local sizes = { 64, 64, 64, 64, 64, 64, 64, 594, 594, 594, 1500 }
   local sizes_ipv6 = { 104, 104, 104, 104, 104, 104, 104, 634, 634, 634, 1540 }
   function opt.S (arg)
      sizes = {}
      sizes_ipv6 = {}
      for size in string.gmatch(arg, "%d+") do
         local s = tonumber(size)
         if s < 28 then
            s = 28
            print("Warning: Increasing IPv4 packet size to 28")
         end
         sizes[#sizes+1] = s
         sizes_ipv6[#sizes_ipv6+1] = s + 40
      end
   end

   local src_mac = "00:00:00:00:00:00"
   function opt.s (arg) src_mac = arg end

   local dst_mac = "00:00:00:00:00:00"
   function opt.d (arg) dst_mac = arg end

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

   local ipv4_only = false
   function opt.v4 () ipv4_only = true end
   opt["4"] = opt.v4

   local ipv6_only = false
   function opt.v6 () ipv6_only = true end
   opt["6"] = opt.v6

   local vlan = nil
   function opt.v (arg) 
      vlan = assert(tonumber(arg), "duration is not a number!")
   end

   local pcap_file, single_pass
   function opt.o (arg) 
      pcap_file = arg
      target = pcap_file
      single_pass = true
   end

   args = lib.dogetopt(args, opt, "VD:hS:s:a:d:b:iI:c:r:46p:v:o:t:i:k:", long_opts)

   if not target then
      print("either --pci, --tap, --sock, --int or --pcap are required parameters")
      main.exit(1)
   end

   print(string.format("packetblaster lwaftr: Sending %d clients at %.3f MPPS to %s", count, rate, target))
   print()

   if not ipv4_only then
      print(string.format("IPv6: %s > %s: %s:%d > %s:12345", b4_ipv6, aftr_ipv6, b4_ipv4, b4_port, public_ipv4))
      print("      source IPv6 and source IPv4/Port adjusted per client")
      print("IPv6 packet sizes: " .. table.concat(sizes_ipv6,","))
   end

   if not ipv6_only then
      print()
      print(string.format("IPv4: %s:12345 > %s:%d", public_ipv4, b4_ipv4, b4_port))
      print("      destination IPv4 and Port adjusted per client")
      print("IPv4 packet sizes: " .. table.concat(sizes,","))
   end

   if ipv4_only and ipv6_only then
      print("Remove options v4only and v6only to generate both")
      main.exit(1)
   end

   config.app(c, "generator", Lwaftrgen, { 
      sizes = sizes, count = count, aftr_ipv6 = aftr_ipv6, rate = rate,
      src_mac = src_mac, dst_mac = dst_mac, vlan = vlan,
      b4_ipv6 = b4_ipv6, b4_ipv4 = b4_ipv4, b4_port = b4_port,
      public_ipv4 = public_ipv4, single_pass = single_pass,
      ipv4_only = ipv4_only, ipv6_only = ipv6_only })

   local input, output

   if tap_interface then
      if dir_exists(("/sys/devices/virtual/net/%s"):format(tap_interface)) then
         config.app(c, "tap", Tap, tap_interface)
         input, output = "tap.input", "tap.output"
      else
         print(string.format("tap interface %s doesn't exist", tap_interface))
         main.exit(1)
      end
   elseif pciaddr then
      local device_info = pci.device_info(pciaddr)
      if vlan then
         print(string.format("vlan set to %d", vlan))
      end
      if device_info then
         config.app(c, "nic", require(device_info.driver).driver,
         {pciaddr = pciaddr, vmdq = false, macaddr = src_mac, mtu = 9500})
         input, output = "nic.rx", "nic.tx"
      else
         fatal(("Couldn't find device info for PCI or tap device %s"):format(pciaddr))
      end
   elseif int_interface then
      config.app(c, "int", raw.RawSocket, int_interface)
      input, output = "int.rx", "int.tx"
   elseif sock_interface then
      config.app(c, "virtio", VhostUser, { socket_path=sock_interface } )
      input, output = "virtio.rx", "virtio.tx"
   else
      config.app(c, "pcap", pcap.PcapWriter, pcap_file)
      input, output = "pcap.input", "pcap.output"
   end

   config.link(c, output .. " -> generator.input")
   config.link(c, "generator.output -> " .. input)

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

   if duration then engine.main({duration=duration})
   else             engine.main() end
end
