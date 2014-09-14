module(...,package.seeall)

local lib      = require("core.lib")
local freelist = require("core.freelist")
local buffer   = require("core.buffer")
local packet   = require("core.packet")
                 require("apps.solarflare.ef_vi_h")
local pci      = require("lib.hardware.pci")
local ethernet = require("lib.protocol.ethernet")

local ffi = require("ffi")
local C = ffi.C

local EVENTS_PER_POLL = 256
local RECEIVE_BUFFER_COUNT = 256
local FLUSH_RECEIVE_QUEUE_THRESHOLD = 32
local TX_BUFFER_COUNT = 256

local ciul = ffi.load("ciul")

local ef_vi_version = ffi.string(ciul.ef_vi_version_str())
print("ef_vi loaded, version " .. ef_vi_version)

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

events = ffi.new("ef_event[" .. EVENTS_PER_POLL .. "]")
tx_request_ids = ffi.new("ef_request_id[" .. C.EF_VI_TRANSMIT_BATCH .. "]")

SolarFlareNic = {}
SolarFlareNic.__index = SolarFlareNic
SolarFlareNic.version = ef_vi_version

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

   args.receives_enqueued = 0
   local dev = setmetatable(args, { __index = SolarFlareNic })
   return dev:open()
end

-- Allocate receive buffers from the given freelist.
function SolarFlareNic:set_rx_buffer_freelist (fl)
   assert(fl)
   self.rx_buffer_freelist = fl
end

function SolarFlareNic:enqueue_receive(id)
   local fl = self.rx_buffer_freelist
   if fl then
      if freelist.nfree(fl) > 0 then
         self.rxbuffers[id] = freelist.remove(fl)
      else
         return
      end
   else
      self.rxbuffers[id] = buffer.allocate()
   end
   try(self.ef_vi_receive_init(self.ef_vi_p,
                               buffer.physical(self.rxbuffers[id]),
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
   for i = 0, packet.niovecs(p) - 1 do
      assert(not self.tx_packets[self.tx_id], "tx buffer overrun")
      self.tx_packets[self.tx_id] = packet.ref(p)
      local iov = packet.iovec(p, i)
      try(ciul.ef_vi_transmit_init(self.ef_vi_p,
                                   buffer.physical(iov.buffer) + iov.offset,
                                   iov.length,
                                   self.tx_id),
          "ef_vi_transmit_init")
      self.tx_id = (self.tx_id + 1) % TX_BUFFER_COUNT
   end
   self.tx_space = self.tx_space - packet.niovecs(p)
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
   try(ciul.ef_pd_alloc_by_name(self.pd_p,
                                self.driver_handle,
                                self.ifname,
                                C.EF_PD_DEFAULT + C.EF_PD_PHYS_MODE),
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

   local broadcast_mac_p = ffi.new("unsigned char[6]")
   broadcast_mac_p[0] = 255
   broadcast_mac_p[1] = 255
   broadcast_mac_p[2] = 255
   broadcast_mac_p[3] = 255
   broadcast_mac_p[4] = 255
   broadcast_mac_p[5] = 255
   filter_spec_p = ffi.new("ef_filter_spec[1]")
   ciul.ef_filter_spec_init(filter_spec_p, C.EF_FILTER_FLAG_NONE)
   try(ciul.ef_filter_spec_set_eth_local(filter_spec_p,
                                         C.EF_FILTER_VLAN_ID_ANY,
                                         broadcast_mac_p),
       "ef_filter_spec_set_eth_local")

   try(ciul.ef_vi_filter_add(self.ef_vi_p,
                             self.driver_handle,
                             filter_spec_p,
                             nil),
       "ef_vi_filter_add")

   self.memregs = {}

   -- cache ops
   self.ef_vi_eventq_poll = self.ef_vi_p[0].ops.eventq_poll
   self.ef_vi_receive_init = self.ef_vi_p[0].ops.receive_init
   self.ef_vi_receive_push = self.ef_vi_p[0].ops.receive_push
   self.ef_vi_transmit_push = self.ef_vi_p[0].ops.transmit_push

   -- initialize statistics
   self.stats = {}

   -- set up receive buffers
   self.rxbuffers = {}
   for id = 1, RECEIVE_BUFFER_COUNT do
      self.enqueue_receive(self, id)
   end
   self.flush_receives(self)

   -- set up transmit variables
   self.tx_packets = {}
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
   try(ciul.ef_vi_free(self.ef_vi_p, self.driver_handle),
       "ef_vi_free")
   try(ciul.ef_pd_free(self.pd_p, self.driver_handle),
       "ef_pd_free")
   try(ciul.ef_driver_close(self.driver_handle),
       "ef_driver_close")
end

local band = bit.band

-- Access to ef_event structure without using C bitfields

local function ef_event_type(event)
   return event.shorts[0];
end

local function ef_event_q_id(event)
   return event.shorts[1];
end

local function ef_event_rx_rq_id(event)
   return event.longs[1];
end

local function ef_event_rx_len(event)
   return event.shorts[4];
end

local function ef_event_rx_flags(event)
   return event.shorts[5];
end

function SolarFlareNic:pull()
   self.stats.pull = (self.stats.pull or 0) + 1
   repeat
      local n_ev = self.ef_vi_eventq_poll(self.ef_vi_p, events, EVENTS_PER_POLL)
--      self.stats.max_n_ev = math.max(n_ev, self.stats.max_n_ev or 0)
      if n_ev > 0 then
         for i = 0, n_ev - 1 do
            local event = events[i]
            local event_type = ef_event_type(event)
            if event_type == C.EF_EVENT_TYPE_RX then
               self.stats.rx = (self.stats.rx or 0) + 1
               if band(ef_event_rx_flags(event), C.EF_EVENT_FLAG_SOP) == 1 then
                  self.rxpacket = packet.allocate()
               else
                  assert(self.rxpacket, "no rxpacket in device, non-SOP buffer received")
               end
               packet.add_iovec(self.rxpacket,
                                self.rxbuffers[ef_event_rx_rq_id(event)],
                                ef_event_rx_len(event))
               if band(ef_event_rx_flags(event), C.EF_EVENT_FLAG_CONT) == 0 then
                  if not link.full(self.output.tx) then
                     link.transmit(self.output.tx, self.rxpacket)
                  else
                     self.stats.link_full = (self.stats.link_full or 0) + 1
                     packet.deref(self.rxpacket)
                  end
                  self.rxpacket = nil
               end
               self.enqueue_receive(self, ef_event_rx_rq_id(event))
            elseif event_type == C.EF_EVENT_TYPE_TX then
               local n_tx_done = ciul.ef_vi_transmit_unbundle(self.ef_vi_p,
                                                              event,
                                                              tx_request_ids)
--               self.stats.max_n_tx_done = math.max(n_tx_done, self.stats.max_n_tx_done or 0)
               self.stats.txpackets = (self.stats.txpackets or 0) + n_tx_done
               for i = 0, (n_tx_done - 1) do
                  packet.deref(self.tx_packets[tx_request_ids[i]])
                  self.tx_packets[tx_request_ids[i]] = nil
               end
               self.tx_space = self.tx_space + n_tx_done
            elseif event_type == C.EF_EVENT_TYPE_TX_ERROR then
               self.stats.tx_error = (self.stats.tx_error or 0) + 1
            else
               print("Unexpected event, type " .. event_type)
            end
         end
      end
      if self.receives_enqueued >= FLUSH_RECEIVE_QUEUE_THRESHOLD then
         self.stats.rx_flushes = (self.stats.rx_flushes or 0) + 1
         self.flush_receives(self)
      end
   until n_ev < EVENTS_PER_POLL
end

local p, push

function SolarFlareNic:push()
   self.stats.push = (self.stats.push or 0) + 1
   local l = self.input.rx
   push = false
   while not link.empty(l) and self.tx_space >= packet.niovecs(link.front(l)) do
      p = link.receive(l)
      self.enqueue_transmit(self, p)
      push = true
      -- enqueue_transmit references the packet once for each buffer
      -- that it contains.  Whenever a DMA fishes, the packet is
      -- dereferenced once so that it will be freed when the
      -- transmission of the last buffer has been confirmed.  Thus, it
      -- can be dereferenced here.
      packet.deref(p)
--      self.stats.max_tx_space = math.max(self.tx_space, self.stats.max_tx_space or 0)
--      self.stats.min_tx_space = math.min(self.tx_space, self.stats.min_tx_space or TX_BUFFER_COUNT)
   end
   if link.empty(l) then
      self.stats.link_empty = (self.stats.link_empty or 0) + 1
   end
   if not link.empty(l) and self.tx_space < packet.niovecs(link.front(l)) then
      self.stats.no_tx_space = (self.stats.no_tx_space or 0) + 1
   end
   if push then
      self.ef_vi_transmit_push(self.ef_vi_p)
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

local count = 0

function SolarFlareNic:report()
   print("report on solarflare device", self.ifname)
   
   for name,value in spairs(self.stats) do
      io.write(string.format('%s: %d ', name, value))
   end
   io.write("\n")
   self.stats = {}
end

assert(C.CI_PAGE_SIZE == 4096, "unexpected C.CI_PAGE_SIZE, needs to be 4096")
