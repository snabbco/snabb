-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local counter = require("core.counter")
local ctable = require("lib.ctable")
local ethernet = require("lib.protocol.ethernet")
local bridge_base = require("apps.bridge.base").bridge
local token_bucket = require('lib.token_bucket')
local tsc        = require('lib.tsc')

local nreadable, receive, transmit = link.nreadable, link.receive, link.transmit

local eth_ptr_t = ffi.typeof("$*", ethernet:ctype())

bridge = subClass(bridge_base)
bridge._name = "learning bridge"
bridge.shm = {
   ["packets-flooded"] = { counter },
   ["packets-discarded"] = { counter },
   ["addresses-learned"] = { counter },
}

local mac_params = {
   size = { default = 1024 },
   timeout = { default = 600 },
   max_occupy = { default = 0.4 },
   verbose = { default = false },
}

local MAC_MASK = 0xFFFFFFFFFFFFULL
local function mac2u64(ptr)
   return bit.band(ffi.cast("uint64_t*", ptr)[0], MAC_MASK)
end

-- The number of entries to scan in one pass of exprie_entries()
local scan_chunks = 100

function bridge:new (conf_base)
   local o = bridge:superClass().new(self, conf_base)
   local conf = lib.parse(conf_base.config.mac_table, mac_params)
   o.verbose = conf.verbose
   o.learn = link.new("learn")

   local params = {
      key_type = ffi.typeof("uint64_t"),
      value_type = ffi.typeof[[
         struct {
            uint16_t port;
            uint64_t tstamp; // creation time in TSC ticks
         } __attribute((packed))
      ]],
      initial_size = math.ceil(conf.size / conf.max_occupy),
      max_occupancy_rate = conf.max_occupy,
      resize_callback = function (table, old_size)
         if old_size > 0 then
            o.logger:log(("Resize MAC table %d -> %d"):
                  format(table.size, old_size))
            o.scan_tb:rate(math.ceil(table.size / o.scan_time))
            require("jit").flush()
         end
      end
   }
   o.value = params.value_type()
   o.mac_table = ctable.new(params)

   -- Token bucket and TSC used to purge learned addresses from the
   -- MAC table
   o.scan_time = conf.timeout
   o.scan_tb = token_bucket.new(
      { rate = math.ceil(o.mac_table.size / o.scan_time),
        burst_size = o.mac_table.size / scan_chunks})
   o.tsc = tsc.new()
   o.ticks_per_timeout = o.tsc:tps() * o.scan_time
   o.scan_cursor = 0
   o.scan_tstamp = o.tsc:stamp()
   o.scan_interval = o.tsc:tps() * o.scan_time / scan_chunks + 0ULL
   o.table_tstamp = o.scan_tstamp

   return o
end

function bridge:expire_entries (now)
   local table = self.mac_table
   local cursor = self.scan_cursor
   for i = 1, self.scan_tb:take_burst() do
      local entry
      cursor, entry = table:next_entry(cursor, cursor + 1)
      if entry then
         if now - entry.value.tstamp > self.ticks_per_timeout then
            table:remove_ptr(entry)
         else
            cursor = cursor + 1
         end
      else
         -- Empty slot or end of table
         if cursor == 0 then
            self.table_scan_time = now - self.table_tstamp
            self.table_tstamp = now
            local scan_time_eff =
               self.tsc:to_ns(self.table_scan_time)/1000000000
            if scan_time_eff > self.scan_time * 1.1 then
               self.logger:log(("Nominal table scan time exceeded: "
                                   .."%d expected, %d effective"):
                     format(self.scan_time, tonumber(scan_time_eff)))
            end
            if self.verbose then
               self.logger:log(("MAC table stats "
                                   .."(entries/load/max_displacement): "
                                   .."%d/%f/%d")
                     :format(table.occupancy, table.occupancy/table.size,
                             table.max_displacement))
            end
         end
      end
   end
   self.scan_cursor = cursor
   self.scan_tstamp = now
end

function bridge:push (input, port)
   local table = self.mac_table

   for _ = 1, nreadable(input) do
      local p = receive(input)
      local eth = ffi.cast(eth_ptr_t, p.data)
      local key = mac2u64(eth.ether_shost)
      local entry = table:lookup_ptr(key)
      if not entry then
         transmit(self.learn, p)
      else
         entry.value.port = port.index
         transmit(input, p)
      end
   end

   for _ = 1, nreadable(self.learn) do
      local p = receive(self.learn)
      local eth = ffi.cast(eth_ptr_t, p.data)
      local key = mac2u64(eth.ether_shost)
      -- Don't learn the same address multiple times.  Empirically,
      -- this behaves better than using add() with 'update_allowed' in
      -- terms of JIT traces
      if not table:lookup_ptr(key) then
         local value = self.value
         value.port = port.index
         value.tstamp = self.tsc:stamp()
         table:add(key, value)
         counter.add(self.shm["addresses-learned"])
      end
      transmit(input, p)
   end

   for _ = 1, nreadable(input) do
      local p = receive(input)
      local eth = ffi.cast(eth_ptr_t, p.data)
      local key = mac2u64(eth.ether_dhost)
      local entry = table:lookup_ptr(key)
      if entry then
         transmit(port.egress[entry.value.port], p)
      else
         -- Unkown unicast or multicast, queue for flooding
         transmit(port.queue, p)
      end
   end

   for _ = 1, nreadable(port.queue) do
      -- Use a box to transport the packet into the inner loop when it
      -- gets compiled first to avoid garbage
      self.box[0] = receive(port.queue)
      transmit(port.egress[0], self.box[0])
      for index = 1, self.max_index do
         transmit(port.egress[index], packet.clone(self.box[0]))
      end
      counter.add(self.shm["packets-flooded"])
   end

   for _ = 1, nreadable(self.discard) do
      packet.free(receive(self.discard))
      counter.add(self.shm["packets-discarded"])
   end
end

function bridge:housekeeping()
   local now = self.tsc:stamp()
   if now - self.scan_tstamp > self.scan_interval then
      self:expire_entries(now)
   end
end

function selftest()
   local macs = {}
   local ports_by_addr = {}
   local extra_macs = 6

   local function random_mac_address(group)
      local bytes = {}
      for i = 1, 6 do
         local value = math.random(255)
         if i == 1 then
            value = bit.band(0xFE, value)
         end
         table.insert(bytes, string.format("%02x", value))
      end
      local addr = ethernet:pton(table.concat(bytes, ":"))
      table.insert(macs, { addr = addr, group = group, packets = 0 })
      return addr
   end

   Source = {}

   function Source:new(conf)
      local src, group = conf.src, conf.group
      local p = packet.resize(packet.allocate(), 60)
      local eth = ffi.cast(eth_ptr_t, p.data)
      ffi.copy(eth.ether_shost, src, 6)
      local dst_macs = {}
      for _, mac in ipairs(macs) do
         if ffi.C.memcmp(src, mac.addr, 6) ~= 0 then
            table.insert(dst_macs, mac)
         end
      end
      return setmetatable({ packet = p,
                            eth = eth,
                            src = src,
                            group = group,
                            macs = dst_macs },
         { __index=Source })
   end

   function Source:pull ()
      local o = self.output.output
      for _ = 1, engine.pull_npackets do
         local i = math.random(1, #macs - 1)
         local mac = self.macs[i]
         ffi.copy(self.eth.ether_dhost, mac.addr, 6)
         if mac.group == '' or mac.group ~= self.group then
            mac.packets = mac.packets + 1
         end
         transmit(o, packet.clone(self.packet))
      end
   end

   local Sink = {}

   function Sink:new(dst)
      return setmetatable({ dst = dst, packets = 0 }, { __index = Sink })
   end

   function Sink:push(input)
      for _ = 1, nreadable(input) do
         local p = receive(input)
         local eth = ffi.cast(eth_ptr_t, p.data)
         if ffi.C.memcmp(eth.ether_dhost, self.dst, 6) == 0 then
            self.packets = self.packets + 1
         end
         packet.free(p)
      end
   end

   local c = config.new()

   local bridge_params = {
         ports = { 'p1', 'p2', 'p3' },
         split_horizon_groups = {
            g1 = { 'g1p1', 'g1p2', 'g1p3' },
            g2 = { 'g2p1', 'g2p2', 'g2p3' }
         }
   }
   config.app(c, "bridge", bridge, bridge_params)

   local function suffix(s, g)
      return s..(g and "_"..g or '')
   end

   for _ = 1, extra_macs do random_mac_address() end

   for _, g in ipairs({ '', 'g1', 'g2' }) do
      local ports
      if g ~= '' then
         ports = bridge_params.split_horizon_groups[g]
      else
         ports = bridge_params.ports
      end
      for _, port in ipairs(ports) do
         local addr = random_mac_address(g)
         ports_by_addr[ethernet:ntop(addr)] = port
         config.app(c, suffix('sink', port), Sink, addr)
         config.app(c, suffix('source', port), Source, { src = addr, group = g })
         config.link(c, suffix('source', port)..".output -> bridge."..port)
         config.link(c, "bridge."..port.." -> "..suffix('sink', port)..".output")
      end
   end

   engine.configure(c)
   engine.main({duration = 1})

   local function packets (app, link, dir)
      local at = engine.app_table[app]
      return tonumber(counter.read(at[dir][link].stats.rxpackets))
   end

   for _, mac in ipairs(macs) do
      local addrp = ethernet:ntop(mac.addr)
      local port = ports_by_addr[addrp]
      if port then
         local sink = engine.app_table[suffix('sink', port)]
         assert(mac.packets == sink.packets)
      end
   end

   print("selftest: ok")
end
