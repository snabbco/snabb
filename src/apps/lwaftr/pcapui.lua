local app = require("core.app")
local config = require("core.config")
local pcap = require("apps.pcap.pcap")
local lwaftr = require("apps.lwaftr.lwaftr")
local bt = require("apps.lwaftr.binding_table")
local ipv6 = require("lib.protocol.ipv6")

local conf = require("apps.lwaftr.conf")

local usage="thisapp conf_file inv4.pcap inv6.pcap outv4.pcap outv6.pcap"

function run (parameters)
   if not (#parameters == 6) then print(usage) main.exit(1) end
   local bt_file = parameters[1]
   local conf_file = parameters[2]
   local inv4_pcap = parameters[3]
   local inv6_pcap = parameters[4]
   local outv4_pcap = parameters[5]
   local outv6_pcap = parameters[6]

   -- It's essential to initialize the binding table before the aftrconf
   bt.get_binding_table(bt_file)
   local aftrconf = conf.get_aftrconf(conf_file)

   local c = config.new()
   config.app(c, "capturev4", pcap.PcapReader, inv4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, inv6_pcap)
   config.app(c, "lwaftr", lwaftr.LwAftr, aftrconf)
   config.app(c, "output_filev4", pcap.PcapWriter, outv4_pcap)
   config.app(c, "output_filev6", pcap.PcapWriter, outv6_pcap)

   config.link(c, "capturev4.output -> lwaftr.v4")
   config.link(c, "capturev6.output -> lwaftr.v6")
   config.link(c, "lwaftr.v4 -> output_filev4.input")
   config.link(c, "lwaftr.v6 -> output_filev6.input")

   app.configure(c)
   app.main({duration=1})
   print("done")
end

run(main.parameters)
