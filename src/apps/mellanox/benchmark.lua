-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local connectx = require("apps.mellanox.connectx")
local worker = require("core.worker")
local basic_apps = require("apps.basic.basic_apps")
local lib = require("core.lib")
local numa = require("lib.numa")
local ffi = require("ffi")
local band = bit.band


function sink (pci, cores, nworkers, nqueues, macs, vlans, opt)
   local cfg = mlxconf(pci, nworkers*nqueues, macs, vlans, opt)

   local cores = cores or {}

   local c = config.new()
   config.app(c, "ConnectX", connectx.ConnectX, cfg)
   engine.configure(c)

   for w=1, nworkers do
      worker.start(
         "sink"..w,
         ('require("apps.mellanox.benchmark").sink_worker(%q, %d, %d, %d)')
            :format(pci, cores[w], nqueues, 1+(w-1)*nqueues)
      )
   end

   engine.main()
end     

function sink_worker (pci, core, nqueues, idx)
   if core then numa.bind_to_cpu(core, 'skip') end

   local c = config.new()
   config.app(c, "Sink", basic_apps.Sink)
   local q = idx
   for _=1, nqueues do
      config.app(c, "IO"..q, connectx.IO, {pciaddress=pci, queue="q"..q})
      config.link(c, "IO"..q..".output -> Sink.input"..q)
      q = q + 1
   end
   engine.configure(c)

   engine.main()
end


function source (pci, cores, nworkers, nqueues, macs, vlans, opt, npackets, pktsize, dmacs, dips, sips)
   local cores = cores or {}
   local macs = make_set(macs)
   local vlans = make_set(vlans)
   local dmacs = make_set(dmacs)
   local dvlans = make_set(dvlans)
   local dips = make_set(dips)
   local sips = make_set(sips)
   
   local cfg = mlxconf(pci, nworkers*nqueues, macs, vlans, opt)

   local c = config.new()
   config.app(c, "ConnectX", connectx.ConnectX, cfg)
   engine.configure(c)

   for w=1, nworkers do
      worker.start(
         "source"..w,
         ('require("apps.mellanox.benchmark").source_worker(%q, %d, %d, %d, '
            ..'%q, ' -- pktsize
            ..'%s, %s, %s, %s, %s)') -- dst/src mac/vlan/ip
            :format(pci, cores[w], nqueues, 1+(w-1)*nqueues,
                    pktsize,
                    give(dmacs, nqueues), give(macs, nqueues),
                    give(vlans, nqueues),
                    give(dips, nqueues), give(sips, nqueues))
      )
   end

   engine.main{done=function ()
      local stats = engine.app_table.ConnectX.hca:query_vport_counter()
      return stats.tx_ucast_packets >= npackets end
   end}
   print(("Transmitted %s packets"):format(lib.comma_value(npackets)))
end

function source_worker (pci, core, nqueues, idx, pktsize, dmacs, smacs, vlans, dips, sips)
   if core then numa.bind_to_cpu(core, 'skip') end

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
      config.app(c, "IO"..q, connectx.IO, {pciaddress=pci, queue="q"..q})
      config.link(c, "Source.output"..q.." -> IO"..q..".input")
      q = q + 1
   end
   engine.configure(c)

   engine.main()
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

function Source:default_dmacs () return {"02:00:00:00:01"} end
function Source:default_smacs () return {"02:00:00:00:02"} end
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
   local size = tonumber(conf.packetsize) or error("NYI")
   self.sizes = make_set{size}
   self.dmacs = make_set(#conf.dmacs > 0 and conf.dmacs or self:default_dmacs())
   self.smacs = make_set(#conf.smacs > 0 and conf.smacs or self:default_smacs())
   self.vlans = make_set(#conf.vlans > 0 and conf.vlans or self:default_vlans())
   self.dips = make_set(#conf.dips > 0 and conf.dips or self:default_dips())
   self.smacs = make_set(#conf.sips > 0 and conf.sips or self:default_sips())
   self.buffersize = conf.buffersize
   self.packets = ffi.new("struct packet *[?]", self.buffersize)
   for i=0, self.buffersize do
      self.packets[i] = self:make_packet()
   end
   self.cursor = 0
   return self
end

function Source:make_packet ()
   local ethernet = require("lib.protocol.ethernet")
   local ipv4 = require("lib.protocol.ipv4")
   local size = take(self.sizes)
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
      ttl = 64
      total_length = size - (eth:sizeof() + ffi.sizeof(dot1q))
   }
   ip:checksum()
   local p = packet.allocate()
   packet.append(eth, eth:sizeof())
   packet.append(dot1q, ffi.sizeof(dot1q))
   packet.append(ip, ip:sizeof())
   packet.resize(p, size)
   return p
end

function Source:pull ()
   local cursor = self.cursor
   local mask = self.buffersize
   local packets = self.packets
   for _, output in pairs(self.output) do
      while not link.full(output) do
         link.transmit(output, packet.clone(packets[band(cursor,mask)]))
         cursor = cursor + 1
      end
   end
   self.cursor = band(cursor, mask)
end


function mlxconf (pci, nqueues, macs, vlans, opt)
   local opt = opt or {}

   local queues = {}
   for q=1, nqueues do
      queues[q] = {"q"..q, mac=take(macs), vlan=take(vlans)}
   end

   local cfg = {}
   for k,v in pairs(opt) do
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
