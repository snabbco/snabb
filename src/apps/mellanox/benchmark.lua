-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local connectx = require("apps.mellanox.connectx")
local worker = require("core.worker")
local basic_apps = require("apps.basic.basic_apps")
local lib = require("core.lib")
local numa = require("lib.numa")
local ffi = require("ffi")
local band = bit.band
local counter = require("core.counter")


function sink (pci, cores, nworkers, nqueues, macs, vlans, opt, npackets)
   local cores = cpu_set(cores)
   local macs = make_set(macs)
   local vlans = make_set(vlans)

   local cfg = mlxconf(pci, nworkers*nqueues, macs, vlans, opt)

   local c = config.new()
   config.app(c, "ConnectX", connectx.ConnectX, cfg)
   engine.configure(c)

   for w=1, nworkers do
      worker.start(
         "sink"..w,
         ('require("apps.mellanox.benchmark").sink_worker(%q, %s, %d, %d)')
            :format(pci, take(cores), nqueues, 1+(w-1)*nqueues)
      )
   end

   local stats = engine.app_table.ConnectX.stats

   local startline = npackets/10
   engine.main{no_report=true, done=function () -- warmup
      return counter.read(stats.rxpackets) >= startline
   end}

   local rxpackets_start = counter.read(stats.rxpackets)
   local rxdrop_start = counter.read(stats.rxdrop)
   local rxerrors_start = counter.read(stats.rxerrors)

   local goal = rxpackets_start + npackets
   local start = engine.now()
   engine.main{no_report=true, done=function ()
      return counter.read(stats.rxpackets) >= goal
   end}

   local duration = engine.now() - start
   local rxpackets = counter.read(stats.rxpackets) - rxpackets_start
   local rxdrop = counter.read(stats.rxdrop) - rxdrop_start
   local rxerrors = counter.read(stats.rxerrors) - rxerrors_start
   print(("Received %s packets in %.2f seconds"):format(lib.comma_value(rxpackets), duration))
   print(("Rx Rate is %.3f Mpps"):format(tonumber(rxpackets) / duration / 1e6))
   print(("Rx Drop Rate is %.3f Mpps"):format(tonumber(rxdrop) / duration / 1e6))
   print(("Rx Error Rate is %.3f Mpps"):format(tonumber(rxerrors) / duration / 1e6))
   io.stdout:flush()

   engine.main{duration=1}
end     

function sink_worker (pci, core, nqueues, idx)
   if core then numa.bind_to_cpu(core, 'skip') end
   engine.busywait = true

   local c = config.new()
   config.app(c, "Sink", basic_apps.Sink)
   local q = idx
   for _=1, nqueues do
      config.app(c, "IO"..q, connectx.IO, {pciaddress=pci, queue="q"..q})
      config.link(c, "IO"..q..".output -> Sink.input"..q)
      q = q + 1
   end
   engine.configure(c)

   while true do
      engine.main{no_report=true, duration=1}
   end
end


function source (pci, cores, nworkers, nqueues, macs, vlans, opt, npackets, pktsize, dmacs, dips, sips)
   local cores = cpu_set(cores)
   local macs = make_set(macs)
   local dmacs = make_set(dmacs)
   local vlans = make_set(vlans)
   local dips = make_set(dips)
   local sips = make_set(sips)
   
   local cfg = mlxconf(pci, nworkers*nqueues, macs, vlans, opt)

   local c = config.new()
   config.app(c, "ConnectX", connectx.ConnectX, cfg)
   engine.configure(c)

   for w=1, nworkers do
      worker.start(
         "source"..w,
         ('require("apps.mellanox.benchmark").source_worker(%q, %s, %d, %d, '
            ..'%q, ' -- pktsize
            ..'%s, %s, %s, %s, %s)') -- dst/src mac/vlan/ip
            :format(pci, take(cores), nqueues, 1+(w-1)*nqueues,
                    pktsize,
                    give(dmacs, nqueues), give(macs, nqueues),
                    give(vlans, nqueues),
                    give(dips, nqueues), give(sips, nqueues))
      )
   end

   local stats = engine.app_table.ConnectX.stats

   local startline = npackets/10
   engine.main{no_report=true, done=function () -- warmup
      return counter.read(stats.txpackets) >= startline
   end}

   local txpackets_start = counter.read(stats.txpackets)
   local txdrop_start = counter.read(stats.txdrop)
   local txerrors_start = counter.read(stats.txerrors)

   local goal = txpackets_start + npackets
   local start = engine.now()
   engine.main{no_report=true, done=function ()
      return counter.read(stats.txpackets) >= goal
   end}

   local duration = engine.now() - start
   local txpackets = counter.read(stats.txpackets) - txpackets_start
   local txdrop = counter.read(stats.txdrop) - txdrop_start
   local txerrors = counter.read(stats.txerrors) - txerrors_start
   print(("Transmitted %s packets in %.2f seconds"):format(lib.comma_value(txpackets), duration))
   print(("Tx Rate is %.3f Mpps"):format(tonumber(txpackets) / duration / 1e6))
   print(("Tx Drop Rate is %.3f Mpps"):format(tonumber(txdrop) / duration / 1e6))
   print(("Tx Error Rate is %.3f Mpps"):format(tonumber(txerrors) / duration / 1e6))
   io.stdout:flush()

   engine.main{no_report=true, duration=1}
end

function source_linger (...)
   source(...)
   engine.main()
end

function source_worker (pci, core, nqueues, idx, pktsize, dmacs, smacs, vlans, dips, sips)
   if core then numa.bind_to_cpu(core, 'skip') end
   engine.busywait = true

   local c = config.new()
   config.app(c, "Source", Source, {
      packetsize = pktsize,
      dmacs = dmacs,
      smacs = smacs,
      vlans = vlans,
      dips = dips,
      sips = sips
   })
   local q = idx
   for _=1, nqueues do
      config.app(c, "IO"..q, connectx.IO, {pciaddress=pci, queue="q"..q, packetblaster=true})
      config.link(c, "Source.output"..q.." -> IO"..q..".input")
      q = q + 1
   end
   engine.configure(c)

   while true do
      engine.main{no_report=true, duration=1}
   end
end

Source = {
   config = {
      packetsize = {required=true},
      dmacs = {required=true},
      smacs = {required=true},
      vlans = {required=true},
      dips = {required=true},
      sips = {required=true},
      buffersize = {default=1024} -- must be power of two
   },
   dot1q_t = ffi.typeof[[struct {
      uint16_t pcp_dei_vid;
      uint16_t ethertype;
   } __attribute__((packed))]]
}

function Source:default_dmacs () return {"02:00:00:00:00:01"} end
function Source:default_smacs () return {"02:00:00:00:00:02"} end
function Source:default_vlans () return {0} end
function Source:default_dips ()
   local ips = {}
   for i=1, 200 do ips[#ips+1] = "10.0.1."..i end
   return ips
end
function Source:default_sips ()
   local ips = {}
   for i=1, 200 do ips[#ips+1] = "10.0.2."..i end
   return ips
end

function Source:new (conf)
   local self = setmetatable({}, {__index=Source})
   local size = tonumber(conf.packetsize)
   if size then
      self.sizes = make_set{size}
   elseif conf.packetsize == 'IMIX' then
      self.sizes = make_set{64, 64, 64, 64, 64, 64, 64, 576, 576, 576, 576, 1500}
   else
      error("NYI")
   end
   self.dmacs = make_set(#conf.dmacs > 0 and conf.dmacs or self:default_dmacs())
   self.smacs = make_set(#conf.smacs > 0 and conf.smacs or self:default_smacs())
   self.vlans = make_set(#conf.vlans > 0 and conf.vlans or self:default_vlans())
   self.dips = make_set(#conf.dips > 0 and conf.dips or self:default_dips())
   self.sips = make_set(#conf.sips > 0 and conf.sips or self:default_sips())
   self.buffersize = conf.buffersize
   self.packets = ffi.new("struct packet *[?]", self.buffersize)
   for i=0, self.buffersize-1 do
      self.packets[i] = self:make_packet()
   end
   self.cursor = 0
   return self
end

function Source:make_packet ()
   local ethernet = require("lib.protocol.ethernet")
   local ipv4 = require("lib.protocol.ipv4")
   local size = take(self.sizes) - 4 -- minus (4 byte CRC)
   assert(size > (ethernet:sizeof() + ffi.sizeof(self.dot1q_t) + ipv4:sizeof()))
   local eth = ethernet:new{
      dst = ethernet:pton(take(self.dmacs)),
      src = ethernet:pton(take(self.smacs)),
      type = 0x8100 -- dot1q
   }
   local dot1q = ffi.new(self.dot1q_t)
   dot1q.pcp_dei_vid = lib.htons(take(self.vlans))
   dot1q.ethertype = lib.htons(0x0800) -- IPv4
   local ip = ipv4:new{
      dst = ipv4:pton(take(self.dips)),
      src = ipv4:pton(take(self.sips)),
      ttl = 64,
      total_length = size - (eth:sizeof() + ffi.sizeof(dot1q))
   }
   ip:checksum()
   local p = packet.allocate()
   packet.append(p, eth:header(), eth:sizeof())
   packet.append(p, dot1q, ffi.sizeof(dot1q))
   packet.append(p, ip:header(), ip:sizeof())
   packet.resize(p, size)
   return p
end

function Source:pull ()
   local cursor = self.cursor
   local mask = self.buffersize-1
   local packets = self.packets
   for _, output in pairs(self.output) do
      while not link.full(output) do
         link.transmit(output, packet.clone(packets[band(cursor,mask)]))
         --link.transmit(output, packets[band(cursor,mask)])
         cursor = cursor + 1
      end
   end
   self.cursor = band(cursor, mask)
end

function fwd (pci, cores, nworkers, nqueues, macs, vlans, opt, npackets)
   local cores = cpu_set(cores)
   local macs = make_set(macs)
   local vlans = make_set(vlans)

   local cfg = mlxconf(pci, nworkers*nqueues, macs, vlans, opt)

   local c = config.new()
   config.app(c, "ConnectX", connectx.ConnectX, cfg)
   engine.configure(c)

   for w=1, nworkers do
      worker.start(
         "sink"..w,
         ('require("apps.mellanox.benchmark").fwd_worker(%q, %s, %d, %d)')
            :format(pci, take(cores), nqueues, 1+(w-1)*nqueues)
      )
   end

   local stats = engine.app_table.ConnectX.stats

   local startline = npackets/10
   engine.main{no_report=true, done=function () -- warmup
      return counter.read(stats.rxpackets) >= startline
   end}

   local rxpackets_start = counter.read(stats.rxpackets)
   local rxdrop_start = counter.read(stats.rxdrop)
   local rxerrors_start = counter.read(stats.rxerrors)
   local txpackets_start = counter.read(stats.txpackets)
   local txdrop_start = counter.read(stats.txdrop)
   local txerrors_start = counter.read(stats.txerrors)

   local goal = rxpackets_start + npackets
   local start = engine.now()
   engine.main{no_report=true, done=function ()
      return counter.read(stats.rxpackets) >= goal
   end}

   local duration = engine.now() - start
   local rxpackets = counter.read(stats.rxpackets) - rxpackets_start
   local rxdrop = counter.read(stats.rxdrop) - rxdrop_start
   local rxerrors = counter.read(stats.rxerrors) - rxerrors_start
   print(("Received %s packets in %.2f seconds"):format(lib.comma_value(rxpackets), duration))
   print(("Rx Rate is %.3f Mpps"):format(tonumber(rxpackets) / duration / 1e6))
   print(("Rx Drop Rate is %.3f Mpps"):format(tonumber(rxdrop) / duration / 1e6))
   print(("Rx Error Rate is %.3f Mpps"):format(tonumber(rxerrors) / duration / 1e6))
   local txpackets = counter.read(stats.txpackets) - txpackets_start
   local txdrop = counter.read(stats.txdrop) - txdrop_start
   local txerrors = counter.read(stats.txerrors) - txerrors_start
   print(("Forwarded %s packets in %.2f seconds"):format(lib.comma_value(txpackets), duration))
   print(("Fw Rate is %.3f Mpps"):format(tonumber(txpackets) / duration / 1e6))
   print(("Fw Drop Rate is %.3f Mpps"):format(tonumber(txdrop) / duration / 1e6))
   print(("Fw Error Rate is %.3f Mpps"):format(tonumber(txerrors) / duration / 1e6))
   io.stdout:flush()

   engine.main{duration=1}
end     

function fwd_worker (pci, core, nqueues, idx)
   if core then numa.bind_to_cpu(core, 'skip') end
   engine.busywait = true

   local c = config.new()
   config.app(c, "Forward", Forward)
   local q = idx
   for _=1, nqueues do
      config.app(c, "IO"..q, connectx.IO, {pciaddress=pci, queue="q"..q})
      config.link(c, "IO"..q..".output -> Forward.input"..q)
      config.link(c, "Forward.output"..q.." -> IO"..q..".input")
      q = q + 1
   end
   engine.configure(c)

   while true do
      engine.main{no_report=true, duration=1}
   end
end

Forward = {}

local ethernet = require("lib.protocol.ethernet")

function Forward:new (conf)
   local self = setmetatable({}, {__index=Forward})
   self.eth = ethernet:new{}
   return self
end

function Forward:link ()
   self.input_links, self.output_links = {}, {}
   for name, input in pairs(self.input) do
      if type(name) == 'string' then
         local q = name:match("input([0-9]+)")
         self.input_links[#self.input_links+1] = input
         self.output_links[#self.output_links+1] = self.output["output"..q]
      end
   end
end

function Forward:push ()
   for i = 1, #self.input_links do
      local input, output = self.input_links[i], self.output_links[i]
      while not link.empty(input) do
         local p = link.receive(input)
         local eth = self.eth:new_from_mem(p.data, p.length)
         eth:swap()
         link.transmit(output, p)
      end
   end
end


function mlxconf (pci, nqueues, macs, vlans, opt, force_opt)
   local queues = {}
   for q=1, nqueues do
      queues[q] = {id="q"..q, mac=take(macs), vlan=take(vlans)}
      --print(pci, queues[q].id, queues[q].mac, queues[q].vlan)
   end

   local cfg = {}
   for k,v in pairs(opt or {}) do
      cfg[k] = v
   end
   for k,v in pairs(force_opt or {}) do
      cfg[k] = v
   end
   cfg.pciaddress = pci
   cfg.queues = queues

   return cfg
end

function make_set (items)
   return {idx=1, items=items or {}}
end

function take (set)
   local item = set.items[set.idx]
   set.idx = (set.idx % #set.items) + 1
   return item
end

function give (set, n)
   local a = "{"
   for _=1, n do
      local item = take(set)
      if item then
         local s = (type(item) == 'string')
               and ("%q"):format(item)
                or ("%s"):format(item)
         a = a..(" %s,"):format(s)
      else
         break
      end
   end
   return a.."}"
end

function cpu_set (s)
   local cores = {}
   for core in pairs(numa.parse_cpuset(s or "")) do
      cores[#cores+1] = core
   end
   return make_set(cores)
end