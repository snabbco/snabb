-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local lib      = require("core.lib")
local packet   = require("core.packet")
                 require("apps.solarflare.ef_vi_h")
local pci      = require("lib.hardware.pci")
local ethernet = require("lib.protocol.ethernet")

local ffi = require("ffi")
local C = ffi.C

local RECEIVE_BUFFER_COUNT = 256
local FLUSH_RECEIVE_QUEUE_THRESHOLD = 32
local TX_BUFFER_COUNT = 256

local ciul = ffi.load("ciul")

local ef_vi_version = ffi.string(ciul.ef_vi_version_str())
local required_ef_vi_version = "201502"

if ef_vi_version ~= required_ef_vi_version then
   error(string.format("ef_vi library does not have the correct version identified, need %s, got %s",
                       required_ef_vi_version, ef_vi_version))
end

-- common utility functions

ffi.cdef[[
char *strerror(int errnum);
]]

local function try (rc, message)
   if rc < 0 then
      error(string.format("%s failed: %s", message,
                          ffi.string(C.strerror(ffi.errno()))))
   end
   return rc
end

SolarFlareNic = {}
SolarFlareNic.__index = SolarFlareNic
SolarFlareNic.version = ef_vi_version

-- The `driver' variable is used as a reference to the driver class in
-- order to interchangably use NIC drivers.
driver = SolarFlareNic

function SolarFlareNic:new(args)
   if type(args) == "string" then
      args = config.parse_app_arg(args)
   end

   if not args.ifname then
      local device_info = pci.device_info(args.pciaddr)
      assert(device_info.interface,
             string.format("interface for chosen pci device %s is not up",
                           args.pciaddr))
      args.ifname = device_info.interface
   end

   if args.macaddr then
      self.mac_address = ethernet:pton(args.macaddr)
   end

   if args.vlan then
      self.vlan = args.vlan
   end

   args.receives_enqueued = 0
   local dev = setmetatable(args, { __index = SolarFlareNic })
   return dev:open()
end

function SolarFlareNic:enqueue_receive(id)
   self.rxpackets[id] = packet.allocate()
   try(self.ef_vi_receive_init(self.ef_vi_p,
                               memory.virtual_to_physical(self.rxpackets[id].data),
                               id),
       "ef_vi_receive_init")
   self.receives_enqueued = self.receives_enqueued + 1
end

function SolarFlareNic:flush_receives(id)
   if self.receives_enqueued > 0 then
      self.ef_vi_receive_push(self.ef_vi_p)
      self.receives_enqueued = 0
   end
end

function SolarFlareNic:enqueue_transmit(p)
   assert(self.tx_packets[self.tx_id] == nil, "tx buffer overrun")
   self.tx_packets[self.tx_id] = p
   try(ciul.ef_vi_transmit_init(self.ef_vi_p,
                                memory.virtual_to_physical(p.data),
                                p.length,
                                self.tx_id),
       "ef_vi_transmit_init")
   self.tx_id = (self.tx_id + 1) % TX_BUFFER_COUNT
   self.tx_space = self.tx_space - 1
end

function SolarFlareNic:open()
   local try_ = try
   local function try (rc, message)
      return try_(rc, string.format("%s (if=%s)", message, self.ifname))
   end

   local handle_p = ffi.new("ef_driver_handle[1]")
   try(ciul.ef_driver_open(handle_p), "ef_driver_open")
   self.driver_handle = handle_p[0]
   self.pd_p = ffi.new("ef_pd[1]")

   if not self.vlan then
      self.vlan = C.EF_PD_VLAN_NONE
   end

   try(ciul.ef_pd_alloc_with_vport(self.pd_p,
                                   self.driver_handle,
                                   self.ifname,
                                   C.EF_PD_DEFAULT + C.EF_PD_PHYS_MODE,
                                   self.vlan),
       "ef_pd_alloc_by_name")
   self.ef_vi_p = ffi.new("ef_vi[1]")
   try(ciul.ef_vi_alloc_from_pd(self.ef_vi_p,
                                self.driver_handle,
                                self.pd_p,
                                self.driver_handle,
                                -1,
                                -1,
                                -1,
                                nil,
                                -1,
                                C.EF_VI_TX_PUSH_DISABLE),
       "ef_vi_alloc_from_pd")

   self.ef_vi_p[0].rx_buffer_len = C.PACKET_PAYLOAD_SIZE

   local env_mac = os.getenv("SF_MAC")

   if not self.mac_address then
      if env_mac then
         self.mac_address = ethernet:pton(env_mac)
      else
         self.mac_address = ffi.new("unsigned char[6]")
         try(ciul.ef_vi_get_mac(self.ef_vi_p,
                                self.driver_handle,
                                self.mac_address),
             "ef_vi_get_mac")
      end
   end

   self.mtu = try(ciul.ef_vi_mtu(self.ef_vi_p, self.driver_handle))
   filter_spec_p = ffi.new("ef_filter_spec[1]")
   ciul.ef_filter_spec_init(filter_spec_p, C.EF_FILTER_FLAG_NONE)
   try(ciul.ef_filter_spec_set_eth_local(filter_spec_p,
                                         C.EF_FILTER_VLAN_ID_ANY,
                                         self.mac_address),
       "ef_filter_spec_set_eth_local")

   try(ciul.ef_vi_filter_add(self.ef_vi_p,
                             self.driver_handle,
                             filter_spec_p,
                             nil),
       "ef_vi_filter_add")

   filter_spec_p = ffi.new("ef_filter_spec[1]")
   ciul.ef_filter_spec_init(filter_spec_p, C.EF_FILTER_FLAG_NONE)
   try(ciul.ef_filter_spec_set_multicast_all(filter_spec_p),
       "ef_filter_spec_set_set_mulicast_all")

   try(ciul.ef_vi_filter_add(self.ef_vi_p,
                             self.driver_handle,
                             filter_spec_p,
                             nil),
       "ef_vi_filter_add")

   self.memregs = {}

   -- cache ops
   self.ef_vi_receive_init = self.ef_vi_p[0].ops.receive_init
   self.ef_vi_receive_push = self.ef_vi_p[0].ops.receive_push
   self.ef_vi_transmit_push = self.ef_vi_p[0].ops.transmit_push

   -- set up poll exchange structures
   self.poll_structure = ffi.new("struct device")
   self.poll_structure.vi = self.ef_vi_p

   -- register device with poller
   C.add_device(self.poll_structure, ciul.ef_vi_transmit_unbundle)

   -- initialize statistics
   self.stats = {}

   -- set up receive buffers
   self.rxpackets = ffi.new("struct packet *[?]", RECEIVE_BUFFER_COUNT + 1)
   for id = 1, RECEIVE_BUFFER_COUNT do
      self.enqueue_receive(self, id)
   end
   self.flush_receives(self)

   -- set up transmit variables
   self.tx_packets = ffi.new("struct packet *[?]", TX_BUFFER_COUNT + 1)
   ffi.fill(self.tx_packets, ffi.sizeof(self.tx_packets), 0)
   self.tx_id = 0
   self.tx_space = TX_BUFFER_COUNT

   -- Done
   print(string.format("Opened SolarFlare interface %s (MAC address %02x:%02x:%02x:%02x:%02x:%02x, MTU %d)",
                       self.ifname,
                       self.mac_address[0],
                       self.mac_address[1],
                       self.mac_address[2],
                       self.mac_address[3],
                       self.mac_address[4],
                       self.mac_address[5],
                       self.mtu))

   return self
end

function SolarFlareNic:stop()
   C.drop_device(self.poll_structure);
   try(ciul.ef_vi_free(self.ef_vi_p, self.driver_handle),
       "ef_vi_free")
   try(ciul.ef_pd_free(self.pd_p, self.driver_handle),
       "ef_pd_free")
   try(ciul.ef_driver_close(self.driver_handle),
       "ef_driver_close")
end

local need_poll = 1

local band = bit.band

function SolarFlareNic:pull()
   if need_poll == 1 then
      C.poll_devices()
      need_poll = 0
   end
   self.stats.pull = (self.stats.pull or 0) + 1
   repeat
      local n_ev = self.poll_structure.n_ev
      local pull_npackets = engine.pull_npackets
      if n_ev > 0 then
         for i = 0, n_ev - 1 do
            local event_type = self.poll_structure.events[i].generic.type
            if event_type == C.EF_EVENT_TYPE_RX and pull_npackets > 0 then
               pull_npackets = pull_npackets - 1
               local rxpacket = self.rxpackets[self.poll_structure.events[i].rx.rq_id]
               rxpacket.length = self.poll_structure.events[i].rx.len
               self.stats.rx = (self.stats.rx or 0) + 1
               link.transmit(self.output.tx, rxpacket)
               self.enqueue_receive(self, self.poll_structure.events[i].rx.rq_id)
            elseif event_type == C.EF_EVENT_TYPE_RX and pull_npackets == 0 then
               self.stats.rxdrop = (self.stats.rxdrop or 0) + 1
               self.enqueue_receive(self, self.poll_structure.events[i].rx.rq_id)
            elseif event_type == C.EF_EVENT_TYPE_TX then
               local n_tx_done = self.poll_structure.unbundled_tx_request_ids[i].n_tx_done
               self.stats.txpackets = (self.stats.txpackets or 0) + n_tx_done
               for j = 0, (n_tx_done - 1) do
                  local id = self.poll_structure.unbundled_tx_request_ids[i].tx_request_ids[j]
                  packet.free(self.tx_packets[id])
                  self.tx_packets[id] = nil
               end
               self.tx_space = self.tx_space + n_tx_done
            elseif event_type == C.EF_EVENT_TYPE_TX_ERROR then
               self.stats.tx_error = (self.stats.tx_error or 0) + 1
            else
               error("Unexpected event, type " .. event_type)
            end
         end
      end
      if self.receives_enqueued >= FLUSH_RECEIVE_QUEUE_THRESHOLD then
         self.stats.rx_flushes = (self.stats.rx_flushes or 0) + 1
         self.flush_receives(self)
      end
   until n_ev < C.EVENTS_PER_POLL
end

function SolarFlareNic:push()
   need_poll = 1
   self.stats.push = (self.stats.push or 0) + 1
   local l = self.input.rx
   local push = not link.empty(l)
   while not link.empty(l) and self.tx_space >= 1 do
      self.enqueue_transmit(self, link.receive(l))
   end
   if push then
      self.ef_vi_transmit_push(self.ef_vi_p)
   end
   if link.empty(l) then
      self.stats.link_empty = (self.stats.link_empty or 0) + 1
   end
   if not link.empty(l) and self.tx_space < 1 then
      self.stats.no_tx_space = (self.stats.no_tx_space or 0) + 1
   end
end

function spairs(t, order)
   -- collect the keys
   local keys = {}
   for k in pairs(t) do keys[#keys+1] = k end

   -- if order function given, sort by it by passing the table and keys a, b,
   -- otherwise just sort the keys
   if order then
      table.sort(keys, function(a,b) return order(t, a, b) end)
   else
      table.sort(keys)
   end

   -- return the iterator function
   local i = 0
   return function()
      i = i + 1
      if keys[i] then
         return keys[i], t[keys[i]]
      end
   end
end

function SolarFlareNic:report()
   print("report on solarflare device", self.ifname)
   
   for name,value in spairs(self.stats) do
      io.write(string.format('%s: %d ', name, value))
   end
   io.write("\n")
   self.stats = {}
end

assert(C.CI_PAGE_SIZE == 4096, "unexpected C.CI_PAGE_SIZE, needs to be 4096")
assert(ffi.sizeof("ef_event") == 16)
