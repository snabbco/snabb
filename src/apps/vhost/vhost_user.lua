-- The VhostUser app implements I/O to a QEMU/KVM Virtio-net interface.
--
-- See http://www.virtualopensystems.com/en/solutions/guides/snabbswitch-qemu/

module(...,package.seeall)

local app       = require("core.app")
local link      = require("core.link")
local config    = require("core.config")
local basic_apps= require("apps.basic.basic_apps")
local buffer    = require("core.buffer")
local ffi       = require("ffi")
local freelist  = require("core.freelist")
local intel_app = require("apps.intel.intel_app")
local lib       = require("core.lib")
local packet    = require("core.packet")
local pcap      = require("apps.pcap.pcap")
local pci       = require("lib.hardware.pci")
local register  = require("lib.hardware.register")
local timer     = require("core.timer")
local vfio      = require("lib.hardware.vfio")
local C         = ffi.C

require("lib.virtio.virtio.h")
require("lib.virtio.virtio_vring_h")
require("apps.vhost.vhost_h")
require("apps.vhost.vhost_user_h")

assert(ffi.sizeof("struct vhost_user_msg") == 212, "ABI error")

VhostUser = {}

function VhostUser:new (socket_path)
   local o = { state = 'init',
               msg = ffi.new("struct vhost_user_msg"),
               nfds = ffi.new("int[1]"),
               fds = ffi.new("int[?]", C.VHOST_USER_MEMORY_MAX_NREGIONS),
               socket_path = socket_path,
               callfd = {},
               kickfd = {},
               -- buffer records that are not currently in use
               buffer_recs = freelist.new("struct buffer *", 32*1024),
               -- buffer records populated with available VM memory
               vring_transmit_buffers = freelist.new("struct buffer *", 32*1024)
            }
   return setmetatable(o, {__index = VhostUser})
end

function VhostUser:pull ()
   if not self.connected then
      self:connect()
   else
      self:process_qemu_requests()
      self:poll_vring_packets()
   end
end

-- Try to connect to QEMU.
function VhostUser:connect ()
   local res = C.vhost_user_connect(self.socket_path)
   if res >= 0 then
      self.socket = res
      self.connected = true
   end
end

function VhostUser:poll_vring_packets ()
   if self.vhost_ready then
      self:receive_packets_from_vm()
      self:get_transmit_buffers_from_vm()
      self:transmit_packets_to_vm()
   end
end

-- Receive all available packets from the virtual machine.
function VhostUser:receive_packets_from_vm ()
   assert(self.connected)
   while self.rxavail ~= self.rxring.avail.idx do
      local descriptor_id = self.rxring.avail.ring[self.rxavail % self.rx_vring_num]
      local p = packet.allocate()
      local need_header = true
      local head_idx = nil
      repeat
         debug("received packet idx = " .. tostring(descriptor_id))
         local descriptor = self.rxring.desc[descriptor_id]
         local guest_addr = descriptor.addr
         local snabb_addr = map_from_guest(guest_addr, self.mem_table)
         local pointer = ptr(snabb_addr)
         local len = descriptor.len
         -- This code is not sufficiently general, but here is how it
         -- works: Linux virtio-net driver is sending packets with the
         -- first buffer (the "head") containing only metadata. We
         -- copy this data into the packet struct (and exclude it from
         -- our iovecs).
         --
         -- To return these buffers to Linux it seems that they expect
         -- us to place the first buffer (containing metadata) onto
         -- the 'used' ring and they will rely on chaining with the
         -- NEXT flag to find and reclaim all the buffers for this
         -- packet.
         --
         -- I'm a little surprised/confused/annoyed that buffers
         -- aren't returned individually, which would seem to make
         -- life simpler. I may be missing something though. -luke
         if need_header then
            if len ~= ffi.sizeof("struct virtio_net_hdr_mrg_rxbuf") then
               error("NYI packet from VM not according to assumptions. length = " .. tostring(len))
            end
            assert(bit.band(descriptor.flags, C.VIO_DESC_F_NEXT) ~= 0)
            ffi.copy(p.info, pointer, ffi.sizeof("struct packet_info"))
            need_header = false
            head_idx = descriptor_id
         else
            local b = freelist.remove(self.buffer_recs) or lib.malloc("struct buffer")
            b.pointer = pointer
            b.physical = snabb_addr
            b.size = len
            -- Tag the first buffer with the head index that needs to be freed.
            --
            -- This is not optimal: freeing this one buffer will cause
            -- all buffers in the chain to be reused by qemu, so bad
            -- things will happen unless we free all virtio packet
            -- buffers at the same time. Have to develop a more
            -- complete understanding of Virtio and then handle this
            -- in a good way.
            if head_idx then
               b.origin.type = C.BUFFER_ORIGIN_VIRTIO
               b.origin.info.virtio.device_id = self.virtio_device_id
               b.origin.info.virtio.ring_id = 1 -- rxring
               b.origin.info.virtio.descriptor_id = head_idx
               head_idx = nil
            end
            packet.add_iovec(p, b, len)
         end
         descriptor_id = descriptor.next
      until bit.band(descriptor.flags, C.VIO_DESC_F_NEXT) == 0
      self.rxavail = (self.rxavail + 1) % 65536
      if self.output.tx then
         link.transmit(self.output.tx, p)
      else
         debug("droprx", "len", p.length, "niovecs", p.niovecs)
         packet.deref(p)
      end
   end
end

-- Populate the `self.vring_transmit_buffers` freelist with buffers from the VM.
function VhostUser:get_transmit_buffers_from_vm ()
   while self.txavail ~= self.txring.avail.idx do
      -- Extract the first buffer and any that are chained to it via NEXT flag
      local index = self.txring.avail.ring[self.txavail % self.tx_vring_num]
      repeat
         local desc  = self.txring.desc[index]
         local b = freelist.remove(self.buffer_recs) or lib.malloc("struct buffer")
         -- XXX The "headroom" optimization:
         -- We assume that the buffer will later be prepended with a
         -- virtio_net_hdr_mrg_rxbuf struct for transmit to the VM. We
         -- reserve space for this header at the start of the packet,
         -- before buffer.pointer, so that we can fill in the header
         -- later without having to copy/move the rest of the packet
         -- data.
         -- 
         -- This assumption breaks down for multi-buffer packets.
         -- Haven't worked out how to avoid copies there yet.
         local headroom = ffi.sizeof("struct virtio_net_hdr_mrg_rxbuf")
         local addr = map_from_guest(desc.addr, self.mem_table) + headroom
         b.pointer = ffi.cast("char*", addr)
         -- XXX Set physical address to virtual address. This is
         -- broken unless we are using vfio and setting up a 1:1
         -- mapping between virtual and IO addresses (so we have to
         -- make sure that we do that, for now.)
         b.physical = ffi.cast("uint64_t", addr)
         b.size = desc.len - headroom
         -- Track the origin of this buffer so we can do zero-copy tricks.
         b.origin.type = C.BUFFER_ORIGIN_VIRTIO
         b.origin.info.virtio.device_id     = self.virtio_device_id
         b.origin.info.virtio.ring_id       = 0 -- tx ring
         b.origin.info.virtio.descriptor_id = index
         debug("added buffer", "size", desc.len, "flags", desc.flags, "count", freelist.nfree(self.vring_transmit_buffers))
         freelist.add(self.vring_transmit_buffers, b)
         self.txavail = (self.txavail + 1) % 65536
         -- Continue to traverse the descriptor chain
         index = desc.next
      until bit.band(desc.flags, C.VIRTIO_DESC_F_NEXT) == 0
   end
end

-- Prepared argument for writing a 1 to an eventfd.
eventfd_one = ffi.new("uint64_t[1]", {1})

-- Transmit packets from the app input queue to the VM.
function VhostUser:transmit_packets_to_vm ()
   local notify_needed = false
   local l = self.input.rx
   if l == nil then return end
   while not link.empty(l) and (self.txring.used.idx + 1) % 65536 ~= self.txused do
      local p = link.receive(l)
      assert(p.niovecs == 1, "NYI: multi-buffer packets")
      local iovec = p.iovecs[0]
      if self:can_zerocopy_transmit(iovec) then
         local b = iovec.buffer
         assert(b.origin.type == C.BUFFER_ORIGIN_VIRTIO)
         local headroom = ffi.sizeof("struct virtio_net_hdr_mrg_rxbuf")
         local start = b.pointer - headroom
         local mrg = ffi.cast("struct virtio_net_hdr_mrg_rxbuf &", start)
         ffi.copy(mrg, p.info, ffi.sizeof(p.info))
         mrg.num_buffers = 1
         local used = self.txring.used.ring[self.txused]
         used.id = b.origin.info.virtio.descriptor_id
         used.len = iovec.length + headroom
         self.txused = (self.txused + 1) % 65536
      else
         assert(false, "NYI packet copy into vring required")
      end
      notify_needed = true
   end
   if notify_needed then
      debug("notify needed")
      self.txring.used.idx = self.txused
      C.write(self.callfd[0], eventfd_one, 8)
   end
end

function VhostUser:can_zerocopy_transmit (iovec)
   return iovec.buffer.origin.type == C.BUFFER_ORIGIN_VIRTIO
      and iovec.buffer.origin.info.virtio.device_id == self.virtio_device_id
      and iovec.buffer.origin.info.virtio.ring_id == 0
      and iovec.offset == 0
end

-- Return a buffer to the virtual machine.
function VhostUser:return_virtio_buffer (b)
   assert(b.origin.info.virtio.device_id == self.virtio_device_id)
   if b.origin.info.virtio.ring_id == 1 then -- Receive buffer?
      local used = self.rxring.used.ring[self.rxring.used.idx % self.rx_vring_num]
      used.id = b.origin.info.virtio.descriptor_id
      used.len = b.size
      debug("Returned buffer", used.id, self.rxring.used.idx)
      self.rxring.used.idx = (self.rxring.used.idx + 1) % 65536
      -- XXX Call at most once per pull()
      C.write(self.callfd[1], eventfd_one, 8)
   end
end

-- vhost_user protocol request handlers.

-- Table of request code -> name of handler method
handler_names = {
   [C.VHOST_USER_NONE]            = 'none',
   [C.VHOST_USER_GET_FEATURES]    = 'get_features',
   [C.VHOST_USER_SET_FEATURES]    = 'set_features',
   [C.VHOST_USER_SET_OWNER]       = 'set_owner',
   [C.VHOST_USER_RESET_OWNER]     = 'reset_owner',
   [C.VHOST_USER_SET_MEM_TABLE]   = 'set_mem_table',
   [C.VHOST_USER_SET_LOG_BASE]    = 'set_log_base',
   [C.VHOST_USER_SET_LOG_FD]      = 'set_log_fd',
   [C.VHOST_USER_SET_VRING_NUM]   = 'set_vring_num',
   [C.VHOST_USER_SET_VRING_ADDR]  = 'set_vring_addr',
   [C.VHOST_USER_SET_VRING_BASE]  = 'set_vring_base',
   [C.VHOST_USER_GET_VRING_BASE]  = 'get_vring_base',
   [C.VHOST_USER_SET_VRING_KICK]  = 'set_vring_kick',
   [C.VHOST_USER_SET_VRING_CALL]  = 'set_vring_call',
   [C.VHOST_USER_SET_VRING_ERR]   = 'set_vring_err',
   [C.VHOST_USER_NET_SET_BACKEND] = 'net_set_backend',
   [C.VHOST_USER_ECHO]            = 'echo'
}

-- Process all vhost_user requests from QEMU.
function VhostUser:process_qemu_requests ()
   local msg = self.msg
   while C.vhost_user_receive(self.socket, msg, self.fds, self.nfds) >= 0 do
      assert(msg.request >= 0 and msg.request <= C.VHOST_USER_MAX)
      debug("Got vhost_user request", handler_names[msg.request], msg.request)
      local method = self[handler_names[msg.request]]
      if method then
         method(self, msg, self.fds, self.nfds[0])
      else
         error(string.format("vhost_user unrecognized request: %d", msg.request))
      end
   end
end

function VhostUser:none (msg)
end

function VhostUser:get_features (msg)
   msg.size = 8
   msg.u64 = C.VIRTIO_NET_F_MRG_RXBUF + C.VIRTIO_NET_F_CSUM
   -- In future add TSO4/TSO6/UFO/ECN and control channel
   self:reply(msg)
end

function VhostUser:set_features (msg)
   debug("features = " .. tostring(msg.u64))
end

function VhostUser:set_owner (msg)
end

function VhostUser:set_vring_num (msg)
   local n = tonumber(msg.state.num)
   if msg.state.index == 0 then
      self.tx_vring_num = n
   else
      self.rx_vring_num = n
   end
end

function VhostUser:set_vring_call (msg, fds, nfds)
   assert(nfds == 1)
   local idx = tonumber(msg.u64)
   self.callfd[idx] = fds[0]
end

function VhostUser:set_vring_kick (msg, fds, nfds)
   local idx = tonumber(msg.u64)
   assert(idx < 42)
   if nfds == 1 then
      self.kickfd[idx] = fds[0]
   end
end

function VhostUser:set_vring_addr (msg)
   local desc  = map_from_qemu(msg.addr.desc_user_addr, self.mem_table)
   local used  = map_from_qemu(msg.addr.used_user_addr, self.mem_table)
   local avail = map_from_qemu(msg.addr.avail_user_addr, self.mem_table)
   local ring = { desc  = ffi.cast("struct vring_desc *", desc),
                  used  = ffi.cast("struct vring_used &", used),
                  avail = ffi.cast("struct vring_avail &", avail) }
   if msg.addr.index == 0 then
      self.txring = ring
      self.txused = ring.used.idx
   else
      self.rxring = ring
      self.rxused = ring.used.idx
   end
   if self.rxring and self.txring then
      self.vhost_ready = true
      self.virtio_device_id = buffer.add_virtio_device(self)
      debug("Connected and initialized vhost_user.")
   end
end

function VhostUser:set_vring_base (msg)
   debug("set_vring_base", msg.state.index, msg.state.num)
   if msg.state.index == 0 then
      self.txavail = msg.state.num
   else
      self.rxavail = msg.state.num
   end
end

function VhostUser:get_vring_base (msg)
   msg.size = 8
   local n
   if msg.state.index == 0 then n = self.txavail else n = self.rxavail end
   msg.u64 = n or 0
   self:reply(msg)
end

function VhostUser:set_mem_table (msg, fds, nfds)
   self.mem_table = {}
   assert(nfds == msg.memory.nregions)
   for i = 0, msg.memory.nregions - 1 do
      assert(fds[i] > 0) -- XXX vapp_server.c uses 'if'
      local size = msg.memory.regions[i].memory_size
      local pointer = C.vhost_user_map_guest_memory(fds[i], size)
      -- XXX Find a more elegant way to map this as IO memory.
      C.mmap_memory(pointer, size, ffi.cast("uint64_t",pointer), true, true)
      local guest = msg.memory.regions[i].guest_phys_addr
      local qemu = msg.memory.regions[i].userspace_addr
      -- register with vfio
      table.insert(self.mem_table, { guest = guest,
                                     qemu  = qemu,
                                     snabb = ffi.cast("int64_t", pointer),
                                     size  = tonumber(size) })
   end
end

function VhostUser:echo (msg)
   self:reply(msg)
end

function VhostUser:reply (req)
   assert(self.socket)
   req.flags = 5
   C.vhost_user_send(self.socket, req)
end

-- Address space remapping.

function map_to_guest (addr, mem_table)
   for _,m in ipairs(mem_table) do
      if addr >= m.snabb and addr < m.snabb + m.size then
         return addr + m.guest - m.snabb
      end
   end
   error("mapping to guest address failed")
end

function map_from_guest (addr, mem_table)
   for _,m in ipairs(mem_table) do
      if addr >= m.guest and addr < m.guest + m.size then
         return addr + m.snabb - m.guest
      end
   end
   error("mapping to host address failed" .. tostring(ffi.cast("void*",addr)))
end

function map_from_qemu (addr, mem_table)
   for _,m in ipairs(mem_table) do
      if addr >= m.qemu and addr < m.qemu + m.size then
         return addr + m.snabb - m.qemu
      end
   end
   error("mapping to host address failed" .. tostring(ffi.cast("void*",addr)))
end

function getTestPCIID()
   return os.getenv("SNABB_TEST_PCI_ID")
end

function getVhostUserSocketFile()
   return os.getenv("SNABB_VHOST_USER_SOCKET_FILE")
end

function selftest ()
   print("selftest: vhost_user")
   if not vfio.is_vfio_available() then
      print("VFIO not available\nTest skipped")
      os.exit(app.test_skipped_code)
   end
   -- Create an app network that proxies packets between a vhost_user
   -- port (qemu) and an Intel port (in loopback mode). Create
   -- separate pcap traces for packets received from vhost and intel.
   -- 
   -- schema for traffic from the VM:
   -- 
   -- vhost -> tee -> intel
   --           |
   --           v
   --       vhost pcap
   -- 
   -- schema for traffic from the intel NIC:
   -- vhost <- tee <- intel
   --           |
   --           v
   --       intel pcap
   -- 
   local pciid = getTestPCIID()
   if not pciid then
      print("SNABB_TEST_PCI_ID was not set\nTest skipped")
      os.exit(app.test_skipped_code)
   end

   local vhost_user_sock = getVhostUserSocketFile()
   if not vhost_user_sock then
      print("SNABB_VHOST_USER_SOCKET_FILE was not set\nTest skipped")
      os.exit(app.test_skipped_code)
   end

   pci.unbind_device_from_linux(pciid)
   vfio.setup_vfio(pciid)
   vfio.bind_device_to_vfio(pciid)
   local c = config.new()
   config.app(c, "vhost_user", VhostUser, vhost_user_sock)
   config.app(c, "vhost_dump", pcap.PcapWriter, "vhost_vm_dump.cap")
   config.app(c, "vhost_tee", basic_apps.Tee)
   config.app(c, "intel", intel_app.Intel82599, pciid)
   config.app(c, "intel_dump", pcap.PcapWriter, "vhost_nic_dump.cap")
   config.app(c, "intel_tee", basic_apps.Tee)
   config.link(c, "vhost_user.tx -> vhost_tee.input")
   config.link(c, "vhost_tee.dump -> vhost_dump.input")
   config.link(c, "vhost_tee.traffic -> intel.rx")
   config.link(c, "intel.tx -> intel_tee.input")
   config.link(c, "intel_tee.dump -> intel_dump.input")
   config.link(c, "intel_tee.traffic -> vhost_user.rx")
   app.configure(c)
   local vhost_user = app.app_table.vhost_user
   local intel = app.app_table.intel
   intel:set_rx_buffer_freelist(vhost_user.vring_transmit_buffers)
   local fn = function ()
                 local vu = app.apps.vhost_user
                 app.report()
                 if vhost_user.vhost_ready then
                    debug("txavail", vhost_user.txring.avail.idx,
                          "txused", vhost_user.txring.used.idx,
                          "rxavail", vhost_user.rxring.avail.idx,
                          "rxused", vhost_user.rxring.used.idx)
                 end
              end
   timer.init()
   timer.activate(timer.new("report", fn, 1e9, 'repeating'))
   -- For interactive testing, uncommon this line to run without time limit:
   -- app.main()
   app.main({duration = 3.5})
end

function ptr (x) return ffi.cast("void*",x) end

function debug (...)
   print(...)
end

