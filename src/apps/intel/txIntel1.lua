module(...,package.seeall)

local basic_apps= require("apps.basic.basic_apps")
local intel1g= require("apps.intel.intel1g")
local lib= require("core.lib")

Intel1g = {}
Intel1g.__index = Intel1g

driver= Intel1g


function Intel1g:new(arg)

end


function Intel1g:stop()

end


function Intel1g:reconfig(arg)

end


function Intel1g:pull()

end


function Intel1g:push()

end


function Intel1g:report()

end


function selftest()
 print("selftest: txIntel1g")
 local pciaddr= os.getenv("SNABB_INTEL1G_1")
 if not pciaddr then
  print("SNABB_INTEL1G_1 not set")
  os.exit(engine.test_skipped_code)
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
