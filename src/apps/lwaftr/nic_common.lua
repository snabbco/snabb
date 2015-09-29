module(...,package.seeall)

local Intel82599 = require("apps.intel.intel_app").Intel82599
local basic_apps = require("apps.basic.basic_apps")
local bt         = require("apps.lwaftr.binding_table")
local conf       = require("apps.lwaftr.conf")
local config     = require("core.config")
local ethernet   = require("lib.protocol.ethernet")
local lwaftr     = require("apps.lwaftr.lwaftr")

function run(bt_file, conf_file, inet_nic_pci, b4side_nic_pci, opts)
   -- It's essential to initialize the binding table before the aftrconf
   bt.get_binding_table(bt_file)
   local aftrconf = conf.get_aftrconf(conf_file)

   local c = config.new()
   config.app(c, 'inetNic', Intel82599, {
      pciaddr=inet_nic_pci,
      macaddr = ethernet:ntop(aftrconf.aftr_mac_inet_side)})
   config.app(c, 'b4sideNic', Intel82599, {
      pciaddr=b4side_nic_pci,
      macaddr = ethernet:ntop(aftrconf.aftr_mac_b4_side)})
   config.app(c, 'lwaftr', lwaftr.LwAftr, aftrconf)
   config.app(c, 'v6_stats', basic_apps.Statistics)
   config.app(c, 'v4_stats', basic_apps.Statistics)

   config.link(c, 'inetNic.tx -> lwaftr.v4')
   config.link(c, 'b4sideNic.tx -> lwaftr.v6')
   if opts.verbose then
      config.link(c, 'lwaftr.v4 -> v4_stats.input')
      config.link(c, 'v4_stats.output -> inetNic.rx')
      config.link(c, 'lwaftr.v6 -> v6_stats.input')
      config.link(c, 'v6_stats.output -> b4sideNic.rx')
   else
      config.link(c, 'lwaftr.v4 -> inetNic.rx')
      config.link(c, 'lwaftr.v6 -> b4sideNic.rx')
   end
   engine.configure(c)

   if opts.ultra_verbose then
      local function lnicui_info()
         app.report_apps()
      end
      local t = timer.new("report", lnicui_info, 1e9, 'repeating')
      timer.activate(t)
   end

   if opts.duration then
      engine.main({duration=opts.duration, report={showlinks=true}})
   else
      engine.main({report={showlinks=true}})
   end
end
