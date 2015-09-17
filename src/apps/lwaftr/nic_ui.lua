local app = require("core.app")
local config = require("core.config")

local Intel82599 = require("apps.intel.intel_app").Intel82599
local pcap = require("apps.pcap.pcap")

local bt = require("apps.lwaftr.binding_table")
local lwaftr = require("apps.lwaftr.lwaftr")
local conf = require("apps.lwaftr.conf")

local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")

local usage="thisapp binding_table_file conf_file inet_nic_pci b4side_nic_pci"

function run (parameters)
   if not (#parameters == 4) then print(usage) main.exit(1) end
   local bt_file, conf_file, inet_nic_pci, b4side_nic_pci = unpack(parameters)

   -- It's essential to initialize the binding table before the aftrconf
   bt.get_binding_table(bt_file)
   local aftrconf = conf.get_aftrconf(conf_file)

   local c = config.new()
   print("gh1")
   config.app(c, 'inetNic', Intel82599, {pciaddr=inet_nic_pci,
                                         vmdq = true,
                                         macaddr = ethernet:ntop(aftrconf.aftr_mac_inet_side)})
   print("gh2")
   config.app(c, 'b4sideNic', Intel82599, {pciaddr=b4side_nic_pci,
                                           vmdq = true,
                                           macaddr = ethernet:ntop(aftrconf.aftr_mac_b4_side)})
   print("gh3")
   config.app(c, "lwaftr", lwaftr.LwAftr, aftrconf)
   print("gh4")

   config.link(c, 'inetNic.rx -> lwaftr.v4')
   config.link(c, 'b4sideNic.rx -> lwaftr.v6')
   config.link(c, 'lwaftr.v4 -> inetNic.tx')
   config.link(c, 'lwaftr.v6 -> b4sideNic.tx')
   print("linked")

   app.configure(c)
   print("confed")
   app.main({duration=1})
   print("done")
end

run(main.parameters)
