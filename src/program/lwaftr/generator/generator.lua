module(..., package.seeall)

local Intel82599 = require("apps.intel.intel_app").Intel82599
local PcapWriter = require("apps.pcap.pcap").PcapWriter
local config = require("core.config")
local generator = require("apps.lwaftr.generator")
local lib = require("core.lib")
local lwconf = require("apps.lwaftr.conf")

local DEFAUL_MAX_PACKETS = 10

function show_usage(code)
   print(require("program.lwaftr.generator.README_inc"))
   main.exit(code)
end

function parse_args(args)
   local opts, handlers = {}, {}
   function handlers.i()
      opts.from_inet = true
   end
   function handlers.b()
      opts.from_b4 = true
   end
   function handlers.m(arg)
      opts.max_packets = assert(tonumber(arg), "max-packets must be a number")
   end
   function handlers.s(arg)
      opts.packet_size = assert(tonumber(arg), "packet-size must be a number")
   end
   function handlers.D(arg)
      opts.duration = assert(tonumber(arg), "duration must be a number")
   end
   function handlers.p(filename)
      opts.pcap = filename
   end
   function handlers.h()
      show_usage(0)
   end
   args = lib.dogetopt(args, handlers, "ibm:s:D:p:h",
      { ["from-inet"]="i", ["from-b4"]="b",
        ["max-packets"]="m", ["packet-size"]="s",
        duration="D", pcap="p", help="h" })
   return opts, args
end

function run(args)
   local opts, args = parse_args(args)

   if opts.from_inet and opts.from_b4
         or not (opts.from_inet or opts.from_b4) then
      show_usage(1)
   end

   local c = config.new()

   -- Set default max_packets value when printing to pcap.
   if opts.pcap and not opts.max_packets then
      opts.max_packets = DEFAUL_MAX_PACKETS
   end

   local lwaftr_config, start_inet, psid_len, pciaddr
   if opts.from_inet then
      local num_args = 4
      if opts.pcap then num_args = num_args - 1 end
      if #args ~= num_args then
         show_usage(1)
      end
      lwaftr_config, start_inet, psid_len, pciaddr = unpack(args)
      local conf = lwconf.load_lwaftr_config(lwaftr_config)
      config.app(c, "generator", generator.from_inet, {
         dst_mac = conf.aftr_mac_inet_side,
         src_mac = conf.inet_mac,
         start_inet = start_inet,
         psid_len = psid_len,
         max_packets = opts.max_packets,
         num_ips = opts.num_ips,
         packet_size = opts.packet_size,
         vlan_tag = conf.vlan_tagging and conf.v4_vlan_tag,
      })
   end

   local start_b4, br
   if opts.from_b4 then
      local num_args = 6
      if opts.pcap then num_args = num_args - 1 end
      if #args ~= num_args then
         show_usage(1)
      end
      lwaftr_config, start_inet, start_b4, br, psid_len, pciaddr = unpack(args)
      local conf = lwconf.load_lwaftr_config(lwaftr_config)
      config.app(c, "generator", generator.from_b4, {
         src_mac = conf.next_hop6_mac,
         dst_mac = conf.aftr_mac_b4_side,
         start_inet = start_inet,
         start_b4 = start_b4,
         br = br,
         psid_len = psid_len,
         max_packets = opts.max_packets,
         num_ips = opts.num_ips,
         packet_size = opts.packet_size,
         vlan_tag = conf.vlan_tagging and conf.v6_vlan_tag,
      })
   end

   if opts.pcap then
      config.app(c, "pcap", PcapWriter, opts.pcap)
      config.link(c, "generator.output -> pcap.input")
      opts.duration = opts.duration or 1
   else
      config.app(c, "nic", Intel82599, { pciaddr = pciaddr })
      config.link(c, "generator.output -> nic.rx")
   end

   engine.configure(c)
   if opts.duration then
      engine.main({ duration = opts.duration })
   else
      engine.main({ noreport = true })
   end
end
