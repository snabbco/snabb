module(...,package.seeall)

local packet = require("core.packet")
local link = require("core.link")
local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")

--- ### `TestSink` app: Receive and discard packets matching against comparator
TestSink = {} 

function TestSink:new(opts)
   return setmetatable({ opts = opts, seen = 0, errs = { } }, { __index=TestSink })
end

function TestSink:push()
   while not link.empty(self.input.rx) do
      local p = link.receive(self.input.rx)
      local cmp = link.front(self.input.comparator)
      if not cmp then
      elseif packet.length(cmp) ~= packet.length(p) 
         or C.memcmp(packet.data(cmp), packet.data(p), packet.length(cmp)) ~= 0 then
         if not self.opts.fuzzy then
            self:log(cmp,p)
         end
      else
         self.seen = self.seen + 1
         packet.free(link.receive(self.input.comparator))
      end
      packet.free(p)
   end
end

function TestSink:log(a,b)
   local str = "Packets differ\n" .. lib.hexdump(ffi.string(packet.data(a), packet.length(a))) 
      .. "\n" .. lib.hexdump(ffi.string(packet.data(b), packet.length(b)))
      table.insert(self.errs, str)
end

function TestSink:stop()
   if not link.empty(self.input.comparator) then
      table.insert(self.errs, "Packets after " .. tostring(self.seen) .. " were never matched")
   end
end

function harness(app, inputs, comps, opts)
   local pcap = require("apps.pcap.pcap")
   local c = config.new()
   -- reset the engine
   engine.configure(c)
   c = config.new()
   config.app(c, "app", app)
   for i,v in pairs(inputs) do
      config.app(c, ("src%s"):format(i), pcap.PcapReader, v)
      config.link(c, ("src%s.output -> app.%s"):format(i,i))
   end
   for i, v in pairs(comps) do
      config.app(c, ("cmp_%s"):format(i), pcap.PcapReader, v)
      config.app(c, ("sink_%s"):format(i), TestSink)
      config.link(c, ("app.%s -> sink_%s.rx"):format(i,i))
      config.link(c, ("cmp_%s.output -> sink_%s.comparator"):format(i,i))
   end
   engine.configure(c)
   engine.main({ duration = 1, no_report = true })
   results = { }
   count = 0
   for i, _ in pairs(comps) do
      results[i] = engine.app_table[("sink_%s"):format(i)].errs
      count = count + #results[i]
   end
   return count == 0, results
end

function selftest()
   local c = config.new()
   local pcap = require("apps.pcap.pcap")
   
   config.app(c, "sink", TestSink)
   config.app(c, "src", pcap.PcapReader, "apps/testsink/selftest1.pcap")
   config.app(c, "comparator", pcap.PcapReader, "apps/testsink/selftest1.pcap")
   config.link(c, "src.output -> sink.rx")
   config.link(c, "comparator.output -> sink.comparator")
   engine.configure(c)
   engine.main({duration=1, no_report = true })
   assert(#engine.app_table.sink.errs == 0)
   
   engine.configure(config.new())
   config.app(c, "comparator", pcap.PcapReader, "apps/testsink/selftest2.pcap")
   engine.configure(c)
   engine.main({duration=1, no_report = true })
   assert(#engine.app_table.sink.errs == 32)

   engine.configure(config.new())
   config.app(c, "sink", TestSink, { fuzzy = true })
   engine.configure(c)
   engine.main({duration=1, no_report = 1})
   assert(#engine.app_table.sink.errs == 0)

   local tee = require("apps.basic.basic_apps").Tee
   local ok, res = harness(tee, { input = "apps/testsink/selftest1.pcap" }, 
      { 
         out = "apps/testsink/selftest1.pcap", 
         out2 = "apps/testsink/selftest1.pcap" 
      })
   assert(ok)
   assert(#res.out == 0)
   assert(#res.out2 == 0)

   ok, res = harness(tee, { input = "apps/testsink/selftest1.pcap" }, 
      { 
         out = "apps/testsink/selftest1.pcap", 
         out2 = "apps/testsink/selftest2.pcap" 
      })
   assert(not ok)
   assert(#res.out == 0)
   assert(#res.out2 == 32)
end