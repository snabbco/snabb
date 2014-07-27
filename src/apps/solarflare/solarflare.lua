module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local lib      = require("core.lib")
local freelist = require("core.freelist")
local memory   = require("core.memory")
local buffer   = require("core.buffer")
local packet   = require("core.packet")
                 require("apps.solarflare.ef_vi_h")

local EVENTS_PER_POLL = 32
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
      error(string.format("%s failed: %s", message, ffi.string(C.strerror(ffi.errno()))))
   end
   return rc
end

SolarFlareNic = {}
SolarFlareNic.__index = SolarFlareNic
SolarFlareNic.version = ef_vi_version

-- List of open devices is kept to be able to register memory regions with them

open_devices = {}

function SolarFlareNic:new(args)
   assert(args.ifname)
   print('New SolarFlare nic ' .. args.ifname)
   args.receives_enqueued = 0
   local dev = setmetatable(args, { __index = SolarFlareNic })
   return dev:open()
end

function SolarFlareNic:enqueue_receive(id)
   self.rxbuffers[id] = buffer.allocate()
   try(self.ef_vi_receive_init(self.ef_vi_p, buffer.physical(self.rxbuffers[id]), id),
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
      try(ciul.ef_vi_transmit_init(self.ef_vi_p, buffer.physical(iov.buffer) + iov.offset, iov.length, self.tx_id),
          "ef_vi_transmit_init")
      self.tx_id = (self.tx_id + 1) % TX_BUFFER_COUNT
   end
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

   self.mac_address = ffi.new("unsigned char[6]")
   try(ciul.ef_vi_get_mac(self.ef_vi_p,
                          self.driver_handle,
                          self.mac_address),
       "ef_vi_get_mac")
   self.mtu = try(ciul.ef_vi_mtu(self.ef_vi_p, self.driver_handle))

   filter_spec_p = ffi.new("ef_filter_spec[1]")
   ciul.ef_filter_spec_init(filter_spec_p, C.EF_FILTER_FLAG_NONE)
   try(ciul.ef_filter_spec_set_eth_local(filter_spec_p, C.EF_FILTER_VLAN_ID_ANY, self.mac_address),
       "ef_filter_spec_set_eth_local")
   try(ciul.ef_vi_filter_add(self.ef_vi_p, self.driver_handle, filter_spec_p, nil),
       "ef_vi_filter_add")

   self.events = ffi.new("ef_event[" .. EVENTS_PER_POLL .. "]")
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
      self:enqueue_receive(id)
   end
   self:flush_receives()

   -- set up transmit variables
   self.tx_request_ids = ffi.new("ef_request_id[" .. C.EF_VI_TRANSMIT_BATCH .. "]")
   self.tx_packets = {}
   self.tx_id = 0

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
   open_devices[#open_devices + 1] = self

   return self
end

function SolarFlareNic:pull()
   self.stats.pull = (self.stats.pull or 0) + 1
   local n_ev
   repeat
      n_ev = self.ef_vi_eventq_poll(self.ef_vi_p, self.events, EVENTS_PER_POLL)
      if n_ev > 0 then
         for i = 0, n_ev - 1 do
            local e = self.events[i];
            if e.generic.type == C.EF_EVENT_TYPE_RX then
               self.stats.rx = (self.stats.rx or 0) + 1
               local p = packet.allocate()
               local b = self.rxbuffers[e.rx.rq_id]
               packet.add_iovec(p, b, e.rx.len)
               self:enqueue_receive(e.rx.rq_id)
               local l = self.output.output
               if not link.full(l) then
                  link.transmit(l, p)
               else
                  self.stats.link_full = (self.stats.link_full or 0) + 1
                  packet.deref(p)
               end
            elseif e.generic.type == C.EF_EVENT_TYPE_RX_DISCARD then
               self.stats.rx_discard = (self.stats.rx_discard or 0) + 1
            elseif e.generic.type == C.EF_EVENT_TYPE_TX then
               local n_tx_done = ciul.ef_vi_transmit_unbundle(self.ef_vi_p, self.events[i], self.tx_request_ids)
               self.stats.tx = (self.stats.tx or 0) + n_tx_done
               for i = 0, (n_tx_done - 1) do
                  local tx_request_id = self.tx_request_ids[i]
                  packet.deref(self.tx_packets[tx_request_id])
                  self.tx_packets[tx_request_id] = nil
               end
            elseif e.generic.type == C.EF_EVENT_TYPE_TX_ERROR then
               self.stats.tx_error = (self.stats.tx_error or 0) + 1
            else
               print("Unexpected event, type " .. e.generic.type)
            end
         end
      end
   until n_ev < EVENTS_PER_POLL
   if self.receives_enqueued >= FLUSH_RECEIVE_QUEUE_THRESHOLD then
      self.stats.rx_flushes = (self.stats.rx_flushes or 0) + 1
      self:flush_receives()
   end
end

function SolarFlareNic:push()
   self.stats.push = (self.stats.push or 0) + 1
   local l = self.input.input
   local push
   -- FIXME: The self_tx_packets[self.tx_id] check is not sufficient.
   -- There must be enough free tx_packets slots for all buffers in
   -- the next packet on the link.
   while not link.empty(l) and not self.tx_packets[self.tx_id] do
      local p = link.receive(l)
      self:enqueue_transmit(p)
      push = true
      -- enqueue_transmit references the packet once for each buffer
      -- that it contains.  Whenever a DMA fishes, the packet is
      -- dereferenced once so that it will be freed when the
      -- transmission of the last buffer has been confirmed.  Thus, it
      -- can be dereferenced here.
      packet.deref(p)
   end
   if push then
      self.ef_vi_transmit_push(self.ef_vi_p)
   end
end

function SolarFlareNic:report()
   print("report on solarflare device", self.ifname)
   
   for name,value in pairs(self.stats) do
      io.write(string.format('%s: %d ', name, value))
   end
   io.write("\n")
end

assert(C.CI_PAGE_SIZE == 4096)

local old_register_RAM = memory.register_RAM
local registered = {}

function memory.register_RAM(p, physical, size)
   local physical_num = tonumber(ffi.cast('intptr_t', ffi.cast('void *', physical)))
   assert(not registered[physical_num], string.format("duplicate registration for physical address 0x%x", physical_num))
   registered[physical_num] = true
   for _, device in ipairs(open_devices) do
      device.stats.memreg_alloc = (device.stats.memreg_alloc or 0) + 1
      local memreg_p = ffi.new("ef_memreg[1]")
      try(ciul.ef_memreg_alloc(memreg_p,
                               device.driver_handle,
                               device.pd_p,
                               device.driver_handle,
                               p,
                               size), "ef_memreg_alloc")
      assert(tonumber(ffi.cast('intptr_t', ffi.cast('void *', physical)))
             == tonumber(ffi.cast('intptr_t', ffi.cast('void *', memreg_p[0].mr_dma_addrs[0]))),
             "SolarFlare library did not map region to physical address")
      device.memregs[#device.memregs] = memreg_p
   end
   old_register_RAM(p, physical, size)
end
