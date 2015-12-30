-- skeletton for program see
--  https://github.com/SnabbCo/snabbswitch/blob/master/src/doc/getting-started.md

module(...,package.seeall)

local basic= require("apps.basic.basic_apps")
local intel1g= require("apps.intel.intel1g")
--local lib= require("core.lib")


function run()
 print("selftest: txIntel1g")
 local pciaddr= os.getenv("SNABB_INTEL1G_1")
 if not pciaddr then
  print("SNABB_INTEL1G_1 not set")
  main.exit(1)
 end

 local c= config.new()
 print(basic.Source, basic.Sink, intel1g)
 config.app(c, "source", basic.Source)
 config.app(c, "nic", intel1g, {pciaddr=pciaddr, rxburst=512})
 config.link(c, "source.tx->nic.rx")
 engine.configure(c)
 engine.main({duration = 60, report = {showapps = true, showlinks = true, showload= true}})
 print("selftest: done")
 engine.app_table.nic.stop()
 --local li = engine.app_table.nic.input[1]
 local li = engine.app_table.nic.input["rx"]          -- same-same as [1]
 assert(li, "intel1g: no input link")
 local s= link.stats(li)
 print("input link:  txpackets= ", s.txpackets, "  rxpackets= ", s.rxpackets, "  txdrop= ", s.txdrop)
end
