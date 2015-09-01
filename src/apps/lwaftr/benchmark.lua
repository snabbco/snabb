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
   local function report (breaths, bytes, packets, runtime)
      local values = {
         breath_in_nanosecond = ("%.2f"):format(runtime / breaths * 1e6),
         breaths              = lib.comma_value(breaths),
         bytes                = bytes,
         million_packets      = ("%.1f"):format(packets / 1e6),
         packets_per_breath   = ("%.2f"):format(packets / breaths),
         rate_gbps            = ("%.2f"):format((bytes * 8 ) / 1e9 / runtime),
         rate_mpps            = ("%.3f"):format(packets / runtime / 1e6),
         runtime              = ("%.2f"):format(runtime),
      }
      print("\n"..format([[
Processed {million_packets} million packets in {runtime} seconds ({bytes} bytes; {rate_gbps} Gbps)
Made {breaths} breaths: {packets_per_breath} packets per breath; {breath_in_nanosecond} us per breath
Rate(Mpps): {rate_mpps}
      ]], values))
   end

   local start = C.get_monotonic_time()
   engine.main(params)
   local finish = C.get_monotonic_time()

   -- local input = link.stats(engine.app_table.nic2.output.tx)
   -- local input = link.stats(engine.app_table.lwaftr.output.output)
   local input = link.stats(engine.app_table.nic1.input.rx)
   local breaths = tonumber(engine.breaths)
   local bytes = input.txbytes
   local packets = input.txpackets
   local runtime = finish - start
   report(breaths, bytes, packets, runtime)
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
   if #params < 4 then usage() end
   local bt_file, conf_file, pcap_file, pcidev = unpack(params)

   bt.get_binding_table(bt_file)
   local aftrconf = conf.get_aftrconf(conf_file)

   engine.configure(config.new())
   local c = config.new()
   config.app(c, 'lwaftr', lwaftr.LwAftr, aftrconf)
   config.app(c, 'pcap', PcapReader, pcap_file)
   config.app(c, 'repeater_ms', basic_apps.Repeater)
   config.app(c, 'sink', basic_apps.Sink)
   -- Origin
   config.app(c, 'nic1', Intel82599, {
      pciaddr = pcidev,
      vmdq = true,
      macaddr = '22:22:22:22:22:22',
   })
   -- Destination
   config.app(c, 'nic2', Intel82599, {
      pciaddr = pcidev,
      vmdq = true,
      macaddr = '44:44:44:44:44:44',
   })

   config.link(c, 'pcap.output        -> repeater_ms.input')
   config.link(c, 'repeater_ms.output -> lwaftr.input')
   config.link(c, 'lwaftr.output      -> nic1.rx')
   config.link(c, 'nic2.tx            -> sink.in1')

   engine.configure(c)

   print("-- testInternalLoopbackFromPcapFile")
   bench(engine, {duration=5, report={showlinks=true}})
end

testInternalLoopbackFromPcapFile(main.parameters)
