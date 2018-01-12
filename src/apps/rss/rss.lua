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
   }
}
local class_config = {
   name = { required = true },
   filter = { required = true },
   continue = { default = false }
}

local hash_info = {
   -- IPv4
   [0x0800] = {
      addr_offset = 12,
      addr_size = 8
   },
   -- IPv6
   [0x86dd] = {
      addr_offset = 8,
      addr_size = 32
   },
}

function rss:new (config)
   local o = { classes = {},
               links_configured = {},
               queue = link.new("queue"),
               rxpackets = 0,
               rxdrops_filter = 0,
               sync_timer = lib.throttle(1),
               rm_ext_headers = config.remove_extension_headers
             }

   for _, info in pairs(hash_info) do
      info.key_t = ffi.typeof([[
            struct {
               uint8_t addrs[$];
               uint32_t ports;
               uint8_t proto;
            } __attribute__((packed))
         ]], info.addr_size)
      info.key = info.key_t()
      info.hash_fn =
         siphash.make_hash({ size = ffi.sizeof(info.key),
                             key = siphash.random_sip_hash_key() })
   end

   local function add_class (name, match_fn, continue)
      assert(name:match("%w+"), "Illegal class name: "..name)
      table.insert(o.classes, {
                      name = name,
                      match_fn = match_fn,
                      continue = continue,
                      input = link.new(name),
                      output = { n = 0 }
      })
   end

   local classes = { default = true }
   for _, class in ipairs(config.classes) do
      local config = lib.parse(class, class_config)
      assert(not classes[config.name],
             "Duplicate filter class: "..config.name)
      classes[config.name] = true
      add_class(config.name, pf.compile_filter(config.filter),
                config.continue)
   end
   if config.default_class then
      -- Catch-all default filter
      add_class("default", function () return true end)
   end

   return setmetatable(o, { __index = self })
end

function rss:link ()
   for name, l in pairs(self.output) do
      if type(name) == "string" then
         if not self.links_configured[name] then
            self.links_configured[name] = true
            local match = false
            for _, class in ipairs(self.classes) do
               local instance = name:match("^"..class.name.."_(.*)")
               if instance then
                  match = true
                  local weight = instance:match("^%w+_(%d+)$") or 1
                  for _ = 1, weight do
                     table.insert(class.output, l)
                  end
                  -- Avoid calls to lj_tab_len() in distribute()
                  class.output.n = #class.output
               end
            end
            if not match then
               print("Ignoring link (does not match any filters): "..name)
            end
         end
      end
   end

   self.classes_active = {}
   for _, class in ipairs(self.classes) do
      if #class.output > 0 then
         table.insert(self.classes_active, class)
      end
   end

   self.input_tagged = {}
   for name, link in pairs(self.input) do
      if type(name) == "string" then
         local vlan = name:match("^vlan(%d+)$")
         if vlan then
            vlan = tonumber(vlan)
            assert(vlan > 0 and vlan < 4095, "Illegal VLAN id: "..vlan)
         end
         table.insert(self.input_tagged, { link = link, vlan = vlan })
      end
   end
end

local function hash (md)
   local info = hash_info[md.ethertype]
   local hash = 0
   if info then
      ffi.copy(info.key.addrs, md.l3 + info.addr_offset, info.addr_size)
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

function rss:push ()
   local queue = self.queue

   for _, input in ipairs(self.input_tagged) do
      local link, vlan = input.link, input.vlan
      local npackets = nreadable(link)
      self.rxpackets = self.rxpackets + npackets
      for _ = 1, npackets do
         local p = receive(link)
         local md = mdadd(p, self.rm_ext_headers, vlan)
         hash(md)
         transmit(queue, p)
      end
   end

   for _, class in ipairs(self.classes_active) do
      -- Apply the filter to all packets.  If a packet matches, it is
      -- put on the class' input queue.  If the class is of type
      -- "continue" or the packet doesn't match the filter, it is put
      -- back onto the main queue for inspection by the next class.
      for j = 1, nreadable(queue) do
         local p = receive(queue)
         local md = mdget(p)
         if class.match_fn(md.filter_start, md.filter_length) then
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

   if self.sync_timer() then
      counter.set(self.shm.rxpackets, self.rxpackets)
      counter.set(self.shm.rxdrops_filter, self.rxdrops_filter)
   end
end

function selftest ()
   -- TBD
end
