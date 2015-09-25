local app = require("core.app")
local config = require("core.config")
local pcap = require("apps.pcap.pcap")
local basic_apps = require("apps.basic.basic_apps")
local lwaftr = require("apps.lwaftr.lwaftr")
local bt = require("apps.lwaftr.binding_table")
local ipv6 = require("lib.protocol.ipv6")

local conf = require("apps.lwaftr.conf")

local usage="benchui binding.table lwaftr.conf inv4.pcap inv6.pcap"

function run (parameters)
   if not (#parameters == 4) then print(usage) main.exit(1) end
   local bt_file, conf_file, inv4_pcap, inv6_pcap = unpack(parameters)

   -- It's essential to initialize the binding table before the aftrconf
   bt.get_binding_table(bt_file)
   local aftrconf = conf.get_aftrconf(conf_file)

   local c = config.new()
   config.app(c, "capturev4", pcap.PcapReader, inv4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, inv6_pcap)
   config.app(c, "repeaterv4", basic_apps.Repeater)
   config.app(c, "repeaterv6", basic_apps.Repeater)
   config.app(c, "lwaftr", lwaftr.LwAftr, aftrconf)
   config.app(c, "statisticsv4", basic_apps.Statistics)
   config.app(c, "statisticsv6", basic_apps.Statistics)
   config.app(c, "sinkv4", basic_apps.Sink)
   config.app(c, "sinkv6", basic_apps.Sink)

   config.link(c, "capturev4.output -> repeaterv4.input")
   config.link(c, "repeaterv4.output -> lwaftr.v4")
   config.link(c, "lwaftr.v4 -> statisticsv4.input")
   config.link(c, "statisticsv4.output -> sinkv4.input")

   config.link(c, "capturev6.output -> repeaterv6.input")
   config.link(c, "repeaterv6.output -> lwaftr.v6")
   config.link(c, "lwaftr.v6 -> statisticsv6.input")
   config.link(c, "statisticsv6.output -> sinkv6.input")

   app.configure(c)
   app.main({})
end

run(main.parameters)
