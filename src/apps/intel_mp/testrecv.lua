-- Helper module for testing intel_mp driver receive

module(..., package.seeall)

local intel = require("apps.intel_mp.intel_mp")
local basic = require("apps.basic.basic_apps")
local ffi = require("ffi")
local C = ffi.C

function test(pciaddr, qno, vmdq, poolno, macaddr, vlan)
   local c = config.new()
   if vmdq then
      config.app(c, "nic", intel.Intel,
                 { pciaddr=pciaddr,
                   macaddr=macaddr,
                   vlan=vlan,
                   vmdq=true,
                   poolnum=poolno,
                   rxq = qno,
                   rxcounter = qno+1,
                   wait_for_link=true })
   else
      config.app(c, "nic", intel.Intel,
                 { pciaddr=pciaddr,
                   rxq = qno,
                   rxcounter = qno+1,
                   wait_for_link=true })
   end
   config.app(c, "sink", basic.Sink)
   if os.getenv("SNABB_RECV_EXPENSIVE") then
      local filter = require("apps.packet_filter.pcap_filter")
   
      local count = 10
      config.link(c, "nic.output -> filter0.input")
      for i=0,count do
         local n = tostring(i)
         local s = "filter"..n
         config.app(c, s, filter.PcapFilter, { filter = [[ not dst host 10.2.29.1 and not dst host 10.2.50.1 ]]})
      end
      for i=1,count do
         local m = tostring(i-1)
         local n = tostring(i)
         local s = "filter"..m..".output -> filter"..n..".input"
         config.link(c, s)
      end
      config.app(c, "sane", filter.PcapFilter, { filter = [[ src host 172.16.172.3 and dst net 1.2.0.0/16 and ip proto 0 ]] })
      config.link(c, "filter"..tostring(count)..".output -> sane.input")
      config.link(c, "sane.output -> sink.input")
   else
      config.link(c, "nic.output -> sink.input")
   end
   
   engine.configure(c)
   local spinup = os.getenv("SNABB_RECV_SPINUP")
   if spinup then
      engine.main({duration = spinup})
   end
   
   local counters = {
      Intel82599 = { "GPRC", "RXDGPC" },
      Intel1g = { "GPRC", "RPTHC" }
   }
   
   local duration = os.getenv("SNABB_RECV_DURATION") or 2
   local before = {}
   local nic = engine.app_table.nic
   local master = nic.master
   
   if master then
      for _,v in pairs(counters[nic.driver]) do
         before[v] = nic.r[v]()
      end
   end
   
   if os.getenv("SNABB_RECV_DEBUG") then
      for _=1,duration do
         engine.main({duration = 1})
         nic:debug()
      end
   else
      engine.main({duration = duration})
   end
   
   if master then
      for _,v in pairs(counters[nic.driver]) do
         print(string.format("%s %d", v, tonumber(nic.r[v]() - before[v])/duration))
      end
   end
   main.exit(0)
end
