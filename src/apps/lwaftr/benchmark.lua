-- Source -> NIC1 -> NIC2 -> Sink

local Intel82599 = require("apps.intel.intel_app").Intel82599
local PcapReader = require("apps.pcap.pcap").PcapReader
local basic_apps = require("apps.basic.basic_apps")
local bt         = require("apps.lwaftr.binding_table")
local conf       = require("apps.lwaftr.conf")
local ffi        = require("ffi")
local lib        = require("core.lib")
local lwaftr     = require("apps.lwaftr.lwaftr")

local C = ffi.C

local function bench(engine, params)
   local function format (str, t)
      for key, _ in str:gmatch("{([a-zA-Z_]+)}") do
         str = str:gsub("{"..key.."}", t[key])
      end
      return str
   end
   local function report (name, breaths, bytes, packets, runtime)
      local values = {
         name                 = name,
         breath_in_nanosecond = ("%.2f"):format(runtime / breaths * 1e6),
         breaths              = lib.comma_value(breaths),
         bytes                = bytes,
         million_packets      = ("%.1f"):format(packets / 1e6),
         packets_per_breath   = ("%.2f"):format(packets / breaths),
         rate_gbps            = ("%.2f"):format((bytes * 8 ) / 1e9 / runtime),
         rate_mpps            = ("%.3f"):format(packets / runtime / 1e6),
         runtime              = ("%.2f"):format(runtime),
      }
      print("\n"..format([[{name} processed {million_packets} million packets in {runtime} seconds ({bytes} bytes; {rate_gbps} Gbps)
Made {breaths} breaths: {packets_per_breath} packets per breath; {breath_in_nanosecond} us per breath
Rate(Mpps): {rate_mpps}
      ]], values))
   end
   local function report_bench(input, name, engine, finish, start)
      local breaths = tonumber(engine.breaths)
      local bytes = input.txbytes
      -- Don't bother to report on interfaces that were boring
      if bytes == 0 then return nil end
      local packets = input.txpackets
      local runtime = finish - start
      report(name, breaths, bytes, packets, runtime)
   end

   local start = C.get_monotonic_time()
   engine.main(params)
   local finish = C.get_monotonic_time()

   -- local input = link.stats(engine.app_table.nic2.output.tx)
   -- local input = link.stats(engine.app_table.lwaftr.output.output)
   -- local input = link.stats(engine.app_table.nic1.input.rx)

   report_bench(link.stats(engine.app_table.nicv4.input.rx), "nicv4-in", engine, finish, start)
   report_bench(link.stats(engine.app_table.nicv6.input.rx), "nicv6-in", engine, finish, start)
--[[
   report_bench(link.stats(engine.app_table.nicv4.output.tx), "nicv4-out", engine, finish, start)
   report_bench(link.stats(engine.app_table.nicv6.output.tx), "nicv6-out", engine, finish, start)
   report_bench(link.stats(engine.app_table.lwaftr.output.v4), "lwaftrv4-out", engine, finish, start)
   report_bench(link.stats(engine.app_table.lwaftr.output.v6), "lwaftrv6-out", engine, finish, start)
   report_bench(link.stats(engine.app_table.lwaftr.input.v4), "lwaftrv4-in", engine, finish, start)
   report_bench(link.stats(engine.app_table.lwaftr.input.v6), "lwaftrv6-in", engine, finish, start)
--]]
end

local function usage ()
   print([[
Usage: <bt_file> <conf_file> <pcap_file> <pci_dev>

   <bt_file>:   Path to binding table.
   <conf_file>: Path to lwaftr configuration file.
   <pcap_file>: Path to pcap file contain packet/s to be sent.
   <pci_dev>:   PCI ID number of network card.
   ]])
   os.exit()
end

local function testInternalLoopbackFromPcapFile (params)
   if #params < 6 then usage() end
   local bt_file, conf_file, pcapv4_file, pcapv6_file, pcidev_v4, pcidev_v6 = unpack(params)

   bt.get_binding_table(bt_file)
   local aftrconf = conf.get_aftrconf(conf_file)

   engine.configure(config.new())
   local c = config.new()
   config.app(c, 'lwaftr', lwaftr.LwAftr, aftrconf)
   config.app(c, 'pcapv4', PcapReader, pcapv4_file)
   config.app(c, 'pcapv6', PcapReader, pcapv6_file)
   config.app(c, 'repeater_v4', basic_apps.Repeater)
   config.app(c, 'repeater_v6', basic_apps.Repeater)
   config.app(c, 'sink', basic_apps.Sink)

   -- Both nics are full-duplex
   config.app(c, 'nicv4', Intel82599, {
      pciaddr = pcidev_v4,
      vmdq = true,
      macaddr = '22:22:22:22:22:22',
   })

   config.app(c, 'nicv6', Intel82599, {
      pciaddr = pcidev_v6,
      vmdq = true,
      macaddr = '44:44:44:44:44:44',
   })

   config.link(c, 'pcapv4.output      -> repeater_v4.input')
   config.link(c, 'repeater_v4.output -> lwaftr.v4')
   config.link(c, 'lwaftr.v4          -> nicv4.rx')
   config.link(c, 'nicv4.tx           -> sink.in1')

   config.link(c, 'pcapv6.output      -> repeater_v6.input')
   config.link(c, 'repeater_v6.output -> lwaftr.v6')
   config.link(c, 'lwaftr.v6          -> nicv6.rx')
   config.link(c, 'nicv6.tx           -> sink.in1')

   engine.configure(c)

   bench(engine, {duration=5, report={showlinks=true}})
end

testInternalLoopbackFromPcapFile(main.parameters)
