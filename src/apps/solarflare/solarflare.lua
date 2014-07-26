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

local ciul = ffi.load("ciul")

local ef_vi_version = ffi.string(ciul.ef_vi_version_str())
print("ef_vi loaded, version " .. ef_vi_version)

-- common utility functions

ffi.cdef[[
char *strerror(int errnum);
int posix_memalign(uint64_t* memptr, size_t alignment, size_t size);
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
   args.receives_enqueued = 0
   return setmetatable(args, { __index = SolarFlareNic })
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

   -- cache ops
   self.ef_vi_eventq_poll = self.ef_vi_p[0].ops.eventq_poll
   self.ef_vi_receive_init = self.ef_vi_p[0].ops.receive_init
   self.ef_vi_receive_push = self.ef_vi_p[0].ops.receive_push

   self.rxbuffers = {}
   for id = 1, RECEIVE_BUFFER_COUNT do
      self:enqueue_receive(id)
   end
   self:flush_receives()

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
end

function SolarFlareNic:pull()
   local n_ev
   repeat
      n_ev = self.ef_vi_eventq_poll(self.ef_vi_p, self.events, EVENTS_PER_POLL)
      if n_ev > 0 then
         for i = 0, n_ev - 1 do
            local e = self.events[i];
            if e.generic.type == C.EF_EVENT_TYPE_RX then
               local p = packet.allocate()
               local b = self.rxbuffers[e.rx.rq_id]
               packet.add_iovec(p, b, e.rx.len)
               self:enqueue_receive(e.rx.rq_id)
               local l = self.output and self.output.tx
               if l and not link.full(l) then
                  link.transmit(l, p)
                  -- fixme: what if link _is_ full?
               end
            elseif e.generic.type == C.EF_EVENT_TYPE_RX_DISCARD then
               print("RX DISCARD")
            elseif e.generic.type == C.EF_EVENT_TYPE_TX then
               print("TX")
            elseif e.generic.type == C.EF_EVENT_TYPE_TX_ERROR then
               print("TX ERROR")
            else
               print("Unexpected event, type " .. e.generic.type)
            end
         end
      end
   until n_ev < EVENTS_PER_POLL
   if self.receives_enqueued >= FLUSH_RECEIVE_QUEUE_THRESHOLD then
      self:flush_receives()
   end
end

function SolarFlareNic:push()
end

function SolarFlareNic:test()
   local b = buffer.allocate()
   local p = packet.allocate()
   packet.add_iovec(p, b, 100)
   print(string.format("done testing"))
end

assert(C.CI_PAGE_SIZE == 4096)

local old_register_RAM = memory.register_RAM

function memory.register_RAM(p, physical, size)
   for _, device in ipairs(open_devices) do
      local memreg_p = ffi.new("ef_memreg[1]")
      try(ciul.ef_memreg_alloc(memreg_p,
                               device.driver_handle,
                               device.pd_p,
                               device.driver_handle,
                               p,
                               size), "ef_memreg_alloc")
   end
   old_register_RAM(p, physical, size)
end
