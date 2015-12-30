-- skelettons for program see
--  https://github.com/SnabbCo/snabbswitch/blob/master/src/doc/getting-started.md
--  src/program/top/

module(..., package.seeall)

local basic= require("apps.basic.basic_apps")
local intel1g= require("apps.intel.intel1g")
local lib= require("core.lib")
local usage= require("program.txintel1g.Usage_inc")

local long_opts= {
 help = "h"
}

function run(args)
 print("selftest: txintel1g")
 --local pciaddr= os.getenv("SNABB_INTEL1G_1")
 local opt= {}
 function opt.h(arg) print(usage) main.exit(1) end
 args= lib.dogetopt(args, opt, "h", long_opts)
 if #args >1 then print(usage) main.exit(1) end
 local pciaddr= args[1]
 if not pciaddr then
  print("Usage: txintel1g <PCI addr of interface>")
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
 assert(li, "txintel1g: no input link")
 local s= link.stats(li)
 print("input link:  txpackets= ", s.txpackets, "  rxpackets= ", s.rxpackets, "  txdrop= ", s.txdrop)
end
