module(...,package.seeall)

local app    = require("core.app")
local lib    = require("core.lib")
local ffi = require("ffi")
local C   = ffi.C
local buffer = require("core.buffer")
local packet   = require("core.packet")

local timer     = require("core.timer")
local register = require("lib.hardware.register")
local vfio = require("lib.hardware.vfio")
local intel10g = require("apps.intel.intel10g")
local freelist = require("core.freelist")

require("lib.virtio.virtio_vring_h")
require("apps.vhost.vhost_h")
require("apps.vhost.vhost_user_h")

assert(ffi.sizeof("struct vhost_user_msg") == 208, "ABI error")

VhostUser = {}

-- avoid GC
keepalive = {}

function VhostUser:new (socket_path)
   local socket = C.vhost_user_open_socket(socket_path)
   assert(socket >= 0, "failed to open socket: " .. socket_path)
   local o = { state = 'init',
               msg = ffi.new("struct vhost_user_msg"),
               nfds = ffi.new("int[1]"),
               fds = ffi.new("int[?]", C.VHOST_USER_MEMORY_MAX_NREGIONS),
               listen_socket = socket,
               vring_base = {},
               callfd = {},
               kickfd = {},
               -- buffer records that are not currently in use
               buffer_recs = freelist.new("struct buffer *", 32*1024),
               -- buffer records populated with available VM memory
               vm_rxbuffers = freelist.new("struct buffer *", 32*1024)
            }
   return setmetatable(o, {__index = VhostUser})
end

function VhostUser:pull ()
   -- Connected?
   if not self.connected then
      self:poll_accept()
   else
      self:poll_request()
      self:poll_virtio()
   end
end

function VhostUser:poll_accept ()
   local res = C.vhost_user_accept(self.listen_socket)
   if res >= 0 then
      self.socket = res
      self.connected = true
   end
end

function VhostUser:poll_request ()
   local msg = self.msg
   if C.vhost_user_receive(self.socket, msg, self.fds, self.nfds) > 0 then
      -- Got a message
      assert(msg.request >= 0 and msg.request <= C.VHOST_USER_MAX)
      if msg.request ~= 1 then
         print("Got " .. handler_names[msg.request] .. "(" .. msg.request..")")
      end
      local method = self[handler_names[msg.request]]
      if method then
         method(self, msg, self.fds, self.nfds[0])
      else
         print(msg.request, C.VHOST_USER_GET_FEATURES)
         print("vhost_user: no handler for " .. handler_names[msg.request])
      end
   end
end

function VhostUser:poll_virtio ()
   if self.vhost_ready then
      self:poll_virtio_rx()
      self:poll_virtio_tx()
   end
end

function VhostUser:poll_virtio_rx ()
   -- Poll while packets are available
   assert(self.connected)
   while self.rxavail ~= self.rxring.avail.idx do
      -- First descriptor
      local descriptor_id = self.rxring.avail.ring[self.rxavail % self.vring_num]

      -- Create packet.
      -- Assign color.
      -- Install iovecs.
      -- Output.

      -- Copy each descriptor into an iovec
      repeat
         print("idx = " .. tostring(descriptor_id))
         local descriptor = self.rxring.desc[descriptor_id]
         local guest_addr = descriptor.addr
         local snabb_addr = map_from_guest(guest_addr, self.mem_table)
         local len = descriptor.len
         local p = packet.allocate()
         local b = ffi.new("struct buffer")
         table.insert(keepalive, b)
         b.pointer = ptr(snabb_addr)
         b.physical = snabb_addr
         b.size = len
         b.origin.type = C.BUFFER_ORIGIN_VIRTIO
         b.origin.info.virtio.device_id = self.virtio_device_id
         b.origin.info.virtio.ring_id = 1 -- rxring
         b.origin.info.virtio.descriptor_id = descriptor_id
         p.niovecs = 1
         p.iovecs[0].buffer = b
         p.iovecs[0].offset = 0
         p.iovecs[0].length = len
         descriptor_id = descriptor.next
      until descriptor.flags == 0
      self.rxavail = (self.rxavail + 1) % 65536
      -- TODO: output the packet
   end
end

-- Poll transmission towards the VM.
function VhostUser:poll_virtio_tx ()
   -- Extract new transmit buffers.
   while self.txavail ~= self.txring.avail.idx do
      -- Extract a transmit buffer.
      local index = self.txring.avail.ring[self.txavail % self.vring_num]
      repeat
         local desc  = self.txring.desc[index]
         local b = freelist.remove(self.buffer_recs) or lib.malloc("struct buffer")
         local addr = map_from_guest(desc.addr, self.mem_table)
         b.pointer = ffi.cast("char*", addr)
         b.physical = 0 -- XXX need to populate ?
         b.size = desc.len
         b.origin.type = C.BUFFER_ORIGIN_VIRTIO
         b.origin.info.virtio.device_id = self.virtio_device_id
         b.origin.info.virtio.ring_id = 1
         b.origin.info.virtio.descriptor_id = index
         freelist.add(self.vm_rxbuffers, b)
         self.txavail = (self.txavail + 1) % 65536
         print("Pulled a buffer", index, desc.len, self.txavail, desc.next, desc.flags)
         index = desc.next
      until bit.band(desc.flags, C.VIRTIO_DESC_F_NEXT) == 0
   end
   -- Transmit packets
   local transmitted = false
   local l = self.input.rx
   while l and not app.empty(l) and self.txring.used.idx ~= self.txused do
      local p = app.receive(l)
      for i = 0, p.niovecs-1 do
         local iovec = p.iovecs[i]
         local used = self.txring.used.ring[self.txused]
         -- XXX Copy into appropriate buffer if needed
         assert(iovec.buffer.origin.virtio.device_id == self.virtio_device_id)
         assert(iovec.buffer.origin.virtio.ring_id   == 1)
         -- XXX Fix alignment if needed.
         assert(iovec.offset == 0)
         used.id = iovec.buffer.origin.virtio.descriptor_index
         used.len = iovec.len
         self.txused = (self.txused + 1) % 65536
      end
      transmitted = true
   end
   if transmitted then
      self.txring.used.idx = self.txused
      local value = ffi.new("uint64_t[1]") -- XXX cache
      value[0] = 1
      C.write(self.callfd[0], value, 8)
   end
end

function VhostUser:return_virtio_buffer (b)
   assert(b.origin.virtio.device_id == self.virtio_device_id)
   if b.origin.virtio.ring_id == 1 then -- Receive buffer?
      local used = self.rxring.used.ring[self.rxring.used.idx]
      used.id = b.origin.virtio.descriptor_id
      used.len = b.size
      self.rxring.used.idx = (self.rxring.used.idx + 1) % 65536
   end
end

function VhostUser:reply (req)
   assert(self.socket)
   C.vhost_user_send(self.socket, req)
end

-- Handler functions for each request type

function VhostUser:none (msg)
end

function VhostUser:get_features (msg)
   msg.u64 = 0
   self:reply(msg)
end

function VhostUser:set_features (msg)
   print("features = " .. tostring(msg.u64))
end

function VhostUser:set_owner (msg)
end

function VhostUser:set_vring_num (msg)
   self.vring_num = tonumber(msg.state.num)
   print("vring_num = " .. msg.state.num)
end

function VhostUser:set_vring_call (msg, fds, nfds)
   local idx = msg.file.index
   assert(idx < 42)
   assert(nfds == 1)
   self.callfd[idx] = fds[0]
end

function VhostUser:set_vring_kick (msg, fds, nfds)
   local idx = msg.file.index
   assert(idx < 42)
   assert(nfds == 1)
   self.kickfd[idx] = fds[0]
end

function VhostUser:set_vring_addr (msg)
   local desc  = map_from_guest(msg.addr.desc_user_addr, self.mem_table)
   local used  = map_from_guest(msg.addr.used_user_addr, self.mem_table)
   local avail = map_from_guest(msg.addr.avail_user_addr, self.mem_table)
   local ring = { desc  = ffi.cast("struct vring_desc *", desc),
                  used  = ffi.cast("struct vring_used &", used),
                  avail = ffi.cast("struct vring_avail &", avail) }
   if msg.addr.index == 0 then
      self.txring = ring
      self.txavail = 0
      self.txused = 0
   else
      self.rxring = ring
      self.rxavail = 0
      self.rxused = 0
   end
   if self.rxring and self.txring then
      self.vhost_ready = true
      self.virtio_device_id = buffer.add_virtio_device(self)
      print("CONNECTED")
   end
   print("vring", ffi.cast("void*",desc))
   local x = ffi.cast("struct { uint64_t addr; uint32_t len; uint16_t flags; uint16_t next; } *", desc)
   print("vring[0]", x[0].addr, x[0].len, x[0].flags, x[0].next)
end

function VhostUser:set_vring_base (msg)
   self.vring_base[msg.state.index] = msg.state.num
end

function VhostUser:get_vring_base (msg)
   msg.u64 = self.vring_base[msg.state.index] or 0
   self:reply(msg)
end

function VhostUser:set_mem_table (msg, fds, nfds)
   print("set_mem_table", msg)
   self.mem_table = {}
   assert(nfds == msg.memory.nregions)
   for i = 0, msg.memory.nregions - 1 do
      assert(fds[i] > 0) -- XXX vapp_server.c uses 'if'
      local size = msg.memory.regions[i].memory_size
      local pointer = C.vhost_user_map_guest_memory(fds[i], size)
      local guest = msg.memory.regions[i].guest_phys_addr
      -- register with vfio
      table.insert(self.mem_table, { guest = guest,
                                     snabb = ffi.cast("int64_t", pointer),
                                     size  = tonumber(size) })
   end
end

function map_to_guest (addr, mem_table)
   for _,m in ipairs(mem_table) do
      if addr >= m.snabb and addr < m.snabb + m.size then
         return addr + m.guest - m.snabb
      end
   end
   error("mapping to guest address failed")
end

function map_from_guest (addr, mem_table)
--   print("mapping from guest", ptr(addr))
--   print("#mem_table", #mem_table)
   for _,m in ipairs(mem_table) do
--      print(ptr(addr), "guest:", ptr(m.guest), "snabb:", ptr(m.snabb))
      if addr >= m.guest and addr < m.guest + m.size then
         return addr + m.snabb - m.guest
      end
   end
   --error("mapping to host address failed" .. tostring(ffi.cast("void*",addr)))
   return addr
end

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
   [C.VHOST_USER_NET_SET_BACKEND] = 'net_set_backend'
}

function selftest ()
   print("selftest: vhost_user")
   local vu = VhostUser:new("/home/luke/qemu.sock")
   app.apps.vhost_user = app.new(vu)
   -- packet generator, sink
--   app.apps.vhost_user = app.new(VhostUser:new("vapp.sock"))
   app.relink()
   local deadline = lib.timer(1e15)
   local fn = function ()
                 print("REPORT")
                 register.dump(vu.nic.r)
                 register.dump(vu.nic.s, true)
              end
   timer.init()
   timer.activate(timer.new("report", fn, 3e9, 'repeating'))
   repeat
      app.breathe()
--      timer.run()
      C.usleep(1e5)
   until false
end


function ptr (x) return ffi.cast("void*",x) end
