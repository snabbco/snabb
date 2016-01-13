module(...,package.seeall)

local app = require("core.app")
local freelist = require("core.freelist")
local packet = require("core.packet")
local link = require("core.link")
local transmit, receive = link.transmit, link.receive
local lib = require("core.lib")


local ffi = require("ffi")
local C = ffi.C

--- # `Source` app: generate synthetic packets

Source = {}

function Source:new(size)
   size = tonumber(size) or 60
   local data = ffi.new("char[?]", size)
   local p = packet.from_pointer(data, size)
   return setmetatable({size=size, packet=p}, {__index=Source})
end

function Source:pull ()
   for _, o in ipairs(self.output) do
      for i = 1, link.nwritable(o) do
         transmit(o, packet.clone(self.packet))
      end
   end
end

function Source:stop ()
   packet.free(self.packet)
end

--- # `Join` app: Merge multiple inputs onto one output

Join = {}

function Join:new()
   return setmetatable({}, {__index=Join})
end

function Join:push ()
   for _, inport in ipairs(self.input) do
      for n = 1,math.min(link.nreadable(inport), link.nwritable(self.output.out)) do
         transmit(self.output.out, receive(inport))
      end
   end
end

--- ### `Split` app: Split multiple inputs across multiple outputs

-- For each input port, push packets onto outputs. When one output
-- becomes full then continue with the next.
Split = {}

function Split:new ()
   return setmetatable({}, {__index=Split})
end

function Split:push ()
   for _, i in ipairs(self.input) do
      for _, o in ipairs(self.output) do
         for _ = 1, math.min(link.nreadable(i), link.nwritable(o)) do
            transmit(o, receive(i))
         end
      end
   end
end

--- ### `Sink` app: Receive and discard packets

Sink = {}

function Sink:new ()
   return setmetatable({}, {__index=Sink})
end

function Sink:push ()
   for _, i in ipairs(self.input) do
      for _ = 1, link.nreadable(i) do
        local p = receive(i)
        packet.free(p)
      end
   end
end

--- ### `Match` app: Compare packets recieved on rx and comparator
Match = {}

function Match:new(cfg)
   if cfg == "nil" then
      cfg = { mode = "exact" }
   end
   assert(cfg.mode == "exact" or cfg.mode == "monotonic", ("Unsupported mode %s"):format(cfg.mode))
   return setmetatable({ cfg = cfg, seen = 0, errs = { }, done = false }, { __index=Match })
end

function Match:push()
   assert(self.input.rx, "input rx not found")
   assert(self.input.comparator, "input comparator not found")
   if self.cfg.mode == "exact" then
      while not link.empty(self.input.rx) and not link.empty(self.input.comparator) do
         local p = link.receive(self.input.rx)
         local cmp = link.receive(self.input.comparator)
         if packet.length(cmp) ~= packet.length(p) or
            C.memcmp(packet.data(cmp), packet.data(p), packet.length(cmp)) ~= 0 then
            self:log(cmp, p)
         end
         packet.free(p)
         packet.free(cmp)
         self.seen = self.seen + 1
      end
   elseif self.cfg.mode == "monotonic" then
      while not link.empty(self.input.rx) and not link.empty(self.input.comparator) do
         local p = link.receive(self.input.rx)
         local cmp = link.front(self.input.comparator)
         if packet.length(cmp) == packet.length(p) and
            C.memcmp(packet.data(cmp), packet.data(p), packet.length(cmp)) == 0 then
            packet.free(link.receive(self.input.comparator))
            self.seen = self.seen + 1
         end
         packet.free(p)
      end
   end
end

function Match:log(a,b)
   local str = "Packets differ\n" .. lib.hexdump(ffi.string(packet.data(a), packet.length(a)))
      .. "\n" .. lib.hexdump(ffi.string(packet.data(b), packet.length(b)))
      table.insert(self.errs, str)
end

function Match:errors()
   if self.done then return self.errs end
   self.done = true
   if self.cfg.mode == 'exact' then
      if not link.empty(self.input.rx) then
         table.insert(self.errs, ("rx empty, packets after packet %d not matched"):format(self.seen))
      elseif not link.empty(self.input.comparator) then
         table.insert(self.errs, ("comparator empty, packets after packet %d not matched"):format(self.seen))
      end
   elseif self.cfg.mode == 'monotonic' then
      if link.empty(self.input.rx) and not link.empty(self.input.comparator) then
         table.insert(self.errs, ("rx empty, packets after packet %d not matched, extend run time?"):format(self.seen))
      end
   end
   return self.errs
end

--- ### `Tee` app: Send inputs to all outputs

Tee = {}

function Tee:new ()
   return setmetatable({}, {__index=Tee})
end

function Tee:push ()
   noutputs = #self.output
   if noutputs > 0 then
      local maxoutput = link.max
      for _, o in ipairs(self.output) do
         maxoutput = math.min(maxoutput, link.nwritable(o))
      end
      for _, i in ipairs(self.input) do
         for _ = 1, math.min(link.nreadable(i), maxoutput) do
            local p = receive(i)
            maxoutput = maxoutput - 1
            do local output = self.output
               for k = 1, #output do
                  transmit(output[k], k == #output and p or packet.clone(p))
               end
            end
         end
      end
   end
end

--- ### `Repeater` app: Send all received packets in a loop

Repeater = {}

function Repeater:new ()
   return setmetatable({index = 1, packets = {}},
                       {__index=Repeater})
end

function Repeater:push ()
   local i, o = self.input.input, self.output.output
   for _ = 1, link.nreadable(i) do
      local p = receive(i)
      table.insert(self.packets, p)
   end
   local npackets = #self.packets
   if npackets > 0 then
      for i = 1, link.nwritable(o) do
         assert(self.packets[self.index])
         transmit(o, packet.clone(self.packets[self.index]))
         self.index = (self.index % npackets) + 1
      end
   end
end

function Repeater:stop ()
   for i = 1, #self.packets do
      packet.free(self.packets[i])
   end
end

function selftest()
   local pcap = require("apps.pcap.pcap")
   local c = config.new()

   --- Compare the same file
   engine.configure(config.new())
   config.app(c, "sink", Match)
   config.app(c, "src", pcap.PcapReader, "apps/basic/match1.pcap")
   config.app(c, "comparator", pcap.PcapReader, "apps/basic/match1.pcap")
   config.link(c, "src.output -> sink.rx")
   config.link(c, "comparator.output -> sink.comparator")
   engine.configure(c)
   engine.main({duration=1, no_report = true })
   assert(#engine.app_table.sink:errors() == 0)

   --- Compare with broken file
   engine.configure(config.new())
   config.app(c, "sink", Match)
   config.app(c, "src", pcap.PcapReader, "apps/basic/match3.pcap")
   config.app(c, "comparator", pcap.PcapReader, "apps/basic/match1.pcap")
   config.link(c, "src.output -> sink.rx")
   config.link(c, "comparator.output -> sink.comparator")
   engine.configure(c)
   engine.main({duration=1, no_report = true })
   assert(#engine.app_table.sink:errors() == 1)

   --- Compare with no input on rx
   engine.configure(config.new())
   config.app(c, "sink", Match)
   config.app(c, "src", Sink)
   config.app(c, "comparator", pcap.PcapReader, "apps/basic/match1.pcap")
   config.link(c, "src.output -> sink.rx")
   config.link(c, "comparator.output -> sink.comparator")
   engine.configure(c)
   engine.main({ duration=1, no_report = true })
   assert(#engine.app_table.sink:errors() == 1)

   --- Compare with no input on comparator
   engine.configure(config.new())
   config.app(c, "sink", Match)
   config.app(c, "comparator", Sink)
   config.app(c, "src", pcap.PcapReader, "apps/basic/match1.pcap")
   config.link(c, "src.output -> sink.rx")
   config.link(c, "comparator.output -> sink.comparator")
   engine.configure(c)
   engine.main({ duration=1, no_report = true })
   assert(#engine.app_table.sink:errors() == 1)

   --- Compare the same file in monotonic mode
   engine.configure(config.new())
   config.app(c, "sink", Match, { mode = "monotonic" })
   config.app(c, "src", pcap.PcapReader, "apps/basic/match1.pcap")
   config.app(c, "comparator", pcap.PcapReader, "apps/basic/match1.pcap")
   config.link(c, "src.output -> sink.rx")
   config.link(c, "comparator.output -> sink.comparator")
   engine.configure(c)
   engine.main({duration=1, no_report = true })
   assert(#engine.app_table.sink:errors() == 0) 

 --- match2 has half the packets match1 has
   engine.configure(config.new())
   config.app(c, "sink", Match, { mode = "monotonic" })
   config.app(c, "src", pcap.PcapReader, "apps/basic/match1.pcap")
   config.app(c, "comparator", pcap.PcapReader, "apps/basic/match2.pcap")
   config.link(c, "src.output -> sink.rx")
   config.link(c, "comparator.output -> sink.comparator")
   engine.configure(c)
   engine.main({duration=1, no_report = true })
   assert(#engine.app_table.sink:errors() == 0) 

--- match2 has half the packets match1 has
   engine.configure(config.new())
   config.app(c, "sink", Match, { mode = "monotonic" })
   config.app(c, "src", pcap.PcapReader, "apps/basic/match2.pcap")
   config.app(c, "comparator", pcap.PcapReader, "apps/basic/match1.pcap")
   config.link(c, "src.output -> sink.rx")
   config.link(c, "comparator.output -> sink.comparator")
   engine.configure(c)
   engine.main({duration=1, no_report = true })
   assert(#engine.app_table.sink:errors() == 1)
   assert(engine.app_table.sink:errors()[1] == "rx empty, packets after packet 0 not matched, extend run time?")
end
