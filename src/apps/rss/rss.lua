-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local packet   = require("core.packet")
local lib      = require("core.lib")
local counter  = require("core.counter")
local siphash  = require("lib.hash.siphash")
local metadata = require("apps.rss.metadata")
local pf       = require("pf")
local ffi      = require("ffi")

local rshift = bit.rshift
local receive, transmit = link.receive, link.transmit
local nreadable = link.nreadable
local free, clone = packet.free, packet.clone
local mdadd, mdget, mdcopy = metadata.add, metadata.get, metadata.copy
local ether_header_ptr_t = metadata.ether_header_ptr_t


local transport_proto_p = {
   -- TCP
   [6] = true,
   -- UDP
   [17] = true,
   -- SCTP
   [132] = true
}

rss = {
   config = {
      default_class = { default = true },
      classes = { default = {} },
      remove_extension_headers = { default = true }
   },
   shm = {
      rxpackets = { counter, 0},
      rxdrops_filter = { counter, 0}
   },
   push_link = {}
}
local class_config = {
   name = { required = true },
   filter = { required = true },
   continue = { default = false }
}

local function mk_addr_copy_fn (size)
   local str = "return function (dst, src)\n"
   for i = 0, size-1 do
      str = str..string.format("   dst[%d] = src[%d]\n", i, i)
   end
   str = str.."end\n"
   return loadstring(str)()
end

local hash_info = {
   -- IPv4
   [0x0800] = {
      addr_offset = 12,
      -- 64-bit words
      addr_size = 1
   },
   -- IPv6
   [0x86dd] = {
      addr_offset = 8,
      -- 64-bit words
      addr_size = 4
   },
}

local etht_demux = {}

function etht_demux:alloc_l2 ()
   local l2 = ffi.new("struct link *[256]", self.default_queue)
   table.insert(self.l2_anchors, l2)
   return l2
end

local function split (type)
   local hi = bit.rshift(type, 8)
   local lo = bit.band(type, 0x00FF)
   return hi, lo
end

function etht_demux:add (type, link)
   local hi, lo = split(type)
   local l2 = self.l1[hi]
   if l2 == self.default then
      l2 = self:alloc_l2()
      self.l1[hi] = l2
   end
   l2[lo] = link
end

function etht_demux:new (default_queue)
   local o = setmetatable({}, { __index = etht_demux })
   o.default_queue = default_queue
   o.l2_anchors = {}
   o.default = o:alloc_l2()
   o.l1 = ffi.new("struct link **[256]", o.default)
   return o
end

function etht_demux:lookup (type)
   local hi, lo = split(type)
   return self.l1[hi][lo]
end

function rss:new (config)
   local o = { classes = {},
               classes_active = {},
               queue = link.new("queue"),
               rxpackets = 0,
               rxdrops_filter = 0,
               sync_timer = lib.throttle(1),
               rm_ext_headers = config.remove_extension_headers
             }

   for _, info in pairs(hash_info) do
      info.key_t = ffi.typeof([[
            struct {
               uint64_t addrs[$];
               uint32_t ports;
               uint8_t proto;
            } __attribute__((packed))
         ]], info.addr_size)
      info.key = info.key_t()
      info.hash_fn =
         siphash.make_hash({ size = ffi.sizeof(info.key),
                             key = siphash.random_sip_hash_key() })
      info.copy_addr_fn = mk_addr_copy_fn(info.addr_size)
   end

   local function add_class (name, match_fn, continue)
      assert(name:match("%w+"), "Illegal class name: "..name)
      local seq = #o.classes
      table.insert(o.classes, {
                      name = name,
                      match_fn = match_fn,
                      continue = continue,
                      input = link.new(name),
                      output = { n = 0 },
                      seq = seq
      })
   end

   local classes = { default = true }
   for _, class in ipairs(config.classes) do
      local config = lib.parse(class, class_config)
      assert(not classes[config.name],
             "Duplicate filter class: "..config.name)
      classes[config.name] = true
      local match_fn
      local vlans = config.filter:match("^VLAN (.*)$")
      if vlans then
         local expr = ""
         local pf_fn
         for vlan in vlans:split("%s") do
            if (vlan:match("^(%d+)$")) then
               expr = expr.."md.vlan == "..vlan.." or "
            elseif vlan == "BPF" then
               local bpf = config.filter:match("BPF (.*)")
               pf_fn = pf.compile_filter(bpf)
               break
            else
               error(string.format("illegal VLAN ID in filter expression of "..
                                      "class %s: %s", class, vlan))
            end
         end
         expr = expr.."nil"
         match_fn = loadstring("return function(md) return "..expr.." end")()
         if pf_fn then
            match_fn_aux = match_fn
            match_fn = function(md)
               return match_fn_aux(md) and pf_fn(md.filter_start, md.filter_length)
            end
         end
      else
         pf_fn = pf.compile_filter(config.filter)
         match_fn = function(md)
            return pf_fn(md.filter_start, md.filter_length)
         end
      end
      add_class(config.name, match_fn, config.continue)
   end
   if config.default_class then
      -- Catch-all default filter
      add_class("default", function () return true end)
   end

   o.demux_queues = {}

   local function add_queue(name)
      local queue = link.new(name)
      o.demux_queues[name] = queue
      return queue
   end

   local function add_demux(default, types)
      local default_queue = add_queue(default)
      local demux = etht_demux:new(default_queue)
      for _, type in ipairs(types) do
         local queue = add_queue(type.name)
         demux:add(type.type, queue)
      end
      return demux
   end

   o.demux1 = add_demux("default_untagged", {
                           { name = "dot1q",
                             type = 0x8100,
                           },
                           { name = "ipv4",
                             type = 0x0800,
                           },
                           { name = "ipv6",
                             type = 0x86dd,
                           }
   })
   o.demux2 = add_demux("default_tagged", {
                           { name= "ipv4_tagged",
                             type = 0x0800,
                           },
                           { name = "ipv6_tagged",
                             type = 0x86dd,
                           }
   })

   o.nqueues = #o.demux_queues

   return setmetatable(o, { __index = self })
end

local function insert_unique(t, new_elt)
   for _, elt in ipairs(t) do
      if elt == new_elt then
         return
      end
   end
   table.insert(t, new_elt)
end

function rss:link (direction, name)
   if direction == 'input' then
      local vlan = name:match("^vlan(%d+)$")
      if vlan then
         vlan = tonumber(vlan)
         assert(vlan > 0 and vlan < 4095, "Illegal VLAN id: "..vlan)
      end
      self.push_link[name] = function (self, input)
         self:push_with_vlan(input, vlan)
      end
   else
      local match = false
      for _, class in ipairs(self.classes) do
         local instance = name:match("^"..class.name.."_(.*)")
         if instance then
            match = true
            local weight = instance:match("^%w+_(%d+)$") or 1
            for _ = 1, weight do
               table.insert(class.output, self.output[name])
            end
            -- Avoid calls to lj_tab_len() in distribute()
            class.output.n = #class.output

            insert_unique(self.classes_active, class)
         end
      end
      -- Preserve order
      table.sort(self.classes_active, function (a, b)  return a.seq < b.seq end)

      if not match then
         print("Ignoring link (does not match any filters): "..name)
      end
   end
end

function rss:unlink (direction, name)
   if direction == 'input' then
      self.push_link[name] = nil
   else
      -- XXX - undo 'output' case in link()?
   end
end

local function hash (md)
   local info = hash_info[md.ethertype]
   local hash = 0
   if info then
      info.copy_addr_fn(info.key.addrs, ffi.cast("uint64_t*", md.l3 + info.addr_offset))
      if transport_proto_p[md.proto] then
         info.key.ports = ffi.cast("uint32_t *", md.l4)[0]
      else
         info.key.ports = 0
      end
      info.key.proto = md.proto
      -- Our SipHash implementation produces only even numbers to satisfy some
      -- ctable internals.
      hash = rshift(info.hash_fn(info.key), 1)
   end
   md.hash = hash
end

local function distribute (p, links, hash)
   -- This relies on the hash being a 16-bit value
   local index = rshift(hash * links.n, 16) + 1
   transmit(links[index], p)
end

local function md_wrapper(self, demux_queue, queue, vlan)
   local p = receive(demux_queue)
   hash(mdadd(p, self.rm_ext_headers, vlan))
   transmit(queue, p)
end

function rss:push_with_vlan(link, vlan)
   local npackets = nreadable(link)
   self.rxpackets = self.rxpackets + npackets
   local queue = self.queue

   -- Use a do..end blocks here to limit the scopes of locals to avoid
   -- "too many spill slots" trace aborts
   do
      -- Performance tuning: mdadd() needs to be called for every
      -- packet. With a mix of tagged/untagged ipv4/ipv6 traffic, that
      -- function has a number of unbiased branches, leading to
      -- inefficient side traces. We use a branch-free classifier on
      -- the Ethertype to separate packets of each type into separate
      -- queues and process them in separate loops. In each loop,
      -- mdadd() is inlined and compiled for the specifics of that
      -- type of packet, which results in 100% biased branches and
      -- thus no side traces. Note that for this to work, the loops
      -- have to be explicite in the code below to allow the compiler
      -- to produce distinct versions of the inlined function.
      for _ = 1, npackets do
         local p = receive(link)
         local hdr = ffi.cast(ether_header_ptr_t, p.data)
         transmit(self.demux1:lookup(lib.ntohs(hdr.ether.type)), p)
      end

      local dot1q = self.demux_queues.dot1q
      for _ = 1, nreadable(dot1q) do
         local p = receive(dot1q)
         local hdr = ffi.cast(ether_header_ptr_t, p.data)
         transmit(self.demux2:lookup(lib.ntohs(hdr.dot1q.type)), p)
      end

      local demux_queues = self.demux_queues
      do
         local dqueue = demux_queues.default_untagged
         for _ = 1, nreadable(dqueue) do
            md_wrapper(self, dqueue, queue, vlan)
         end
      end
      do
         local dqueue = demux_queues.default_tagged
         for _ = 1, nreadable(dqueue) do
            md_wrapper(self, dqueue, queue, vlan)
         end
      end
      do
         local dqueue = demux_queues.ipv4
         for _ = 1, nreadable(dqueue) do
            md_wrapper(self, dqueue, queue, vlan)
         end
      end
      do
         local dqueue = demux_queues.ipv6
         for _ = 1, nreadable(dqueue) do
            md_wrapper(self, dqueue, queue, vlan)
         end
      end
      do
         local dqueue = demux_queues.ipv4_tagged
         for _ = 1, nreadable(dqueue) do
            md_wrapper(self, dqueue, queue, vlan)
         end
      end
      do
         local dqueue = demux_queues.ipv6_tagged
         for _ = 1, nreadable(dqueue) do
            md_wrapper(self, dqueue, queue, vlan)
         end
      end
   end

   for _, class in ipairs(self.classes_active) do
      -- Apply the filter to all packets.  If a packet matches, it is
      -- put on the class' input queue.  If the class is of type
      -- "continue" or the packet doesn't match the filter, it is put
      -- back onto the main queue for inspection by the next class.
      for _ = 1, nreadable(queue) do
         local p = receive(queue)
         local md = mdget(p)
         if class.match_fn(md) then
            md.ref = md.ref + 1
            transmit(class.input, p)
            if class.continue then
               transmit(queue, p)
            end
         else
            transmit(queue, p)
         end
      end
   end

   for _ = 1, nreadable(queue) do
      local p = receive(queue)
      local md = mdget(p)
      if md.ref == 0 then
         self.rxdrops_filter = self.rxdrops_filter + 1
         free(p)
      end
   end

   for _, class in ipairs(self.classes_active) do
      for _ = 1, nreadable(class.input) do
         local p = receive(class.input)
         local md  = mdget(p)
         if md.ref > 1 then
            md.ref = md.ref - 1
            distribute(mdcopy(p), class.output, md.hash)
         else
            distribute(p, class.output, md.hash)
         end
      end
   end
end

function rss:tick()
   if self.sync_timer() then
      counter.set(self.shm.rxpackets, self.rxpackets)
      counter.set(self.shm.rxdrops_filter, self.rxdrops_filter)
   end
end

function selftest ()
   local vlan_id = 123
   local addr_ip = ffi.new("uint8_t[4]")
   local addr_ip6 = ffi.new("uint8_t[16]")
   local function random_ip(addr)
      for i = 0, ffi.sizeof(addr) - 1 do
         addr[i] = math.random(255)
      end
      return addr
   end

   local ext_hdr = ffi.new([[
     struct {
        uint8_t next_header;
        uint8_t length;
        uint8_t data[14];
     }  __attribute__((packed))
   ]])
   local function push_ext_hdr(dgram, next_header)
      local p = dgram:packet()
      ext_hdr.next_header = next_header
      ext_hdr.length = 1
      local length = ffi.sizeof(ext_hdr)
      p = packet.prepend(p, ext_hdr, length)
      dgram:new(p)
      return length
   end

   local Source = {}

   function Source:new()
      local o = {
         eth = require("lib.protocol.ethernet"):new({}),
         ip = require("lib.protocol.ipv4"):new({ protocol = 17 }),
         ip6 = require("lib.protocol.ipv6"):new({ next_header = 17 }),
         udp = require("lib.protocol.udp"):new({}),
         dgram = require("lib.protocol.datagram"):new()
      }
      return setmetatable(o, {__index=Source})
   end

   function Source:random_packet()
      local p = packet.allocate()
      local payload_size = math.random(9000)
      p.length = payload_size
      self.dgram:new(p)
      self.udp:src_port(math.random(2^16-1))
      self.udp:dst_port(math.random(2^16-1))
      self.dgram:push(self.udp)
      if math.random() > 0.5 then
         self.ip:src(random_ip(addr_ip))
         self.ip:dst(random_ip(addr_ip))
         self.ip:total_length(self.ip:sizeof() + self.udp:sizeof()
                                 + payload_size)
         self.dgram:push(self.ip)
         self.eth:type(0x0800)
      else
         local next_header = 17
         local ext_hdr_size = 0
         for _ = 1, math.ceil(math.random(3)) do
            ext_hdr_size = ext_hdr_size
               + push_ext_hdr(self.dgram, next_header)
            next_header = 0 -- Hop-by-hop header
         end
         self.ip6:payload_length(ext_hdr_size + self.udp:sizeof()
                                    + payload_size)
         self.ip6:next_header(next_header)
         self.ip6:src(random_ip(addr_ip6))
         self.ip6:dst(random_ip(addr_ip6))
         self.dgram:push(self.ip6)
         self.eth:type(0x86dd)
      end
      self.dgram:push(self.eth)
      return self.dgram:packet()
   end

   function Source:pull ()
      for _, o in ipairs(self.output) do
         for i = 1, engine.pull_npackets do
            transmit(o, self:random_packet())
         end
      end
   end

   local Sink = {}

   function Sink:new ()
      return setmetatable({}, { __index = Sink })
   end

   function Sink:push ()
      for _, i in ipairs(self.input) do
         for _ = 1, link.nreadable(i) do
            local p = receive(i)
            local md = mdget(p)
            assert(md.ethertype == 0x0800 or md.ethertype == 0x86dd,
                   md.ethertype)
            assert(md.vlan == 0 or md.vlan == vlan_id)
            local offset = md.vlan == 0 and 0 or 4
            assert(md.filter_offset == offset, md.filter_offset)
            assert(md.filter_start == p.data + offset)
            assert(md.l3 == p.data + 14 + offset)
            assert(md.total_length == p.length - 14 - offset)
            assert(md.filter_length == p.length - offset)
            if md.ethertype == 0x0800 then
               assert(md.l4 == md.l3 + 20)
            else
               assert(md.l4 == md.l3 + 40)
            end
            assert(md.proto == 17)
            assert(md.frag_offset == 0)
            assert(md.length_delta == 0, md.length_delta)
            packet.free(p)
         end
      end
   end

   local graph = config.new()
   config.app(graph, "rss", rss, { classes = {
                                      { name = "ip",
                                        filter = "ip",
                                        continue = true },
                                      { name = "ip6",
                                        filter = "ip6",
                                        continue = true } } })
   config.app(graph, "source1", Source)
   config.app(graph, "source2", Source)
   config.app(graph, "vlan", require("apps.vlan.vlan").Tagger,
              { tag = vlan_id })
   config.link(graph, "source1.output -> rss.input_plain")
   config.link(graph, "source2.output -> vlan.input")
   config.link(graph, "vlan.output -> rss.input_vlan")

   local sink_groups = {
      { name = "default", n = 4},
      { name = "ip", n = 4 },
      { name = "ip6", n = 4 },
   }
   for g, group in ipairs(sink_groups) do
      for i = 1, group.n do
         local sink_name = "sink"..g..i
         config.app(graph, sink_name, Sink)
         config.link(graph, "rss."..group.name.."_"..i
                        .." -> "..sink_name..".input")
      end
   end

   engine.configure(graph)
   engine.main({ duration = 2, report = { showlinks = true } })

   local function pkts(name, dir)
      local app = engine.app_table[name]
      if dir == "out" then
         return tonumber(counter.read(app.output.output.stats.rxpackets))
      else
         return tonumber(counter.read(app.input.input.stats.rxpackets))
      end
   end

   local npackets = pkts("source1", "out") + pkts("source2", "out")
   for g, group in ipairs(sink_groups) do
      for i = 1, group.n do
         local share = npackets/group.n
         if group.name ~= "default" then
            share = share/2
         end
         local sink_name = "sink"..g..i
         local pkts = pkts(sink_name, "in")
         local threshold = 0.05
         local value = math.abs(1.0 - pkts/share)
         if value >= threshold then
            error(string.format("Unexpected traffic share on %s "
                                   .."(expected %f, got %f)",
                                sink_name, threshold, value))
         end
      end
   end
end
