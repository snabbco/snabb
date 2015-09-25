local C = require("ffi").C

local config = require("core.config")
local lib = require("core.lib")

local Intel82599 = require("apps.intel.intel_app").Intel82599
local basic_apps = require("apps.basic.basic_apps")
local pcap = require("apps.pcap.pcap")

local bt = require("apps.lwaftr.binding_table")
local lwaftr = require("apps.lwaftr.lwaftr")
local conf = require("apps.lwaftr.conf")

local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")

local usage="thisapp binding_table_file conf_file inet_nic_pci b4side_nic_pci"

local long_opts = {
   duration     = "D",
   help         = "h",
   verbose      = "v",
   ultraverbose = "u"
}

local duration, verbose, ultra_verbose

local function print_info(app, link)
   if ultra_verbose then
      app.report_apps()
   end
end

function run (parameters)
   local opt = {}
   function opt.v (arg) verbose = true  end
   function opt.u (arg) ultra_verbose = true verbose = true end
   function opt.D (arg) duration = tonumber(arg)  end
   function opt.h (arg) print(usage) main.exit(1) end
   parameters = lib.dogetopt(parameters, opt, "vuhD:", long_opts)

   if not (#parameters == 4) then opt.h(nil) end
   local bt_file, conf_file, inet_nic_pci, b4side_nic_pci = unpack(parameters)

   -- It's essential to initialize the binding table before the aftrconf
   bt.get_binding_table(bt_file)
   local aftrconf = conf.get_aftrconf(conf_file)

   local c = config.new()
   config.app(c, 'inetNic', Intel82599, {pciaddr=inet_nic_pci,
                                         macaddr = ethernet:ntop(aftrconf.aftr_mac_inet_side)})
   config.app(c, 'b4sideNic', Intel82599, {pciaddr=b4side_nic_pci,
                                           macaddr = ethernet:ntop(aftrconf.aftr_mac_b4_side)})
   config.app(c, 'lwaftr', lwaftr.LwAftr, aftrconf)
   config.app(c, 'v6_stats', basic_apps.Statistics)
   config.app(c, 'v4_stats', basic_apps.Statistics)

   config.link(c, 'inetNic.tx -> lwaftr.v4')
   config.link(c, 'b4sideNic.tx -> lwaftr.v6')
   if verbose then
      config.link(c, 'lwaftr.v4 -> v4_stats.input')
      config.link(c, 'v4_stats.output -> inetNic.rx')
      config.link(c, 'lwaftr.v6 -> v6_stats.input')
      config.link(c, 'v6_stats.output -> b4sideNic.rx')
   else
      config.link(c, 'lwaftr.v4 -> inetNic.rx')
      config.link(c, 'lwaftr.v6 -> b4sideNic.rx')
   end

   engine.configure(c)

   if ultra_verbose then
      local function lnicui_info() print_info(engine) end
      local t = timer.new("report", lnicui_info, 1e9, 'repeating')
      timer.activate(t)
   end

   if duration then
      engine.main({duration=duration, report={showlinks=true}})
   else
      engine.main({report={showlinks=true}})
   end
end

run(main.parameters)
