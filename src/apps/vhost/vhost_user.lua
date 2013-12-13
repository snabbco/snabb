module(...,package.seeall)

local app    = require("core.app")
local lib    = require("core.lib")
local ffi = require("ffi")
local C   = ffi.C

require("lib.virtio.virtio_vring_h")
require("apps.vhost.vhost_h")
require("apps.vhost.vhost_user_h")

assert(ffi.sizeof("struct vhost_user_msg") == 208, "ABI error")

VhostUser = {}

function VhostUser:new (socket_path)
   local socket = C.vhost_user_open_socket(socket_path)
   assert(socket >= 0, "failed to open socket: " .. socket_path)
   local o = { state = 'init',
               msg = ffi.new("struct vhost_user_msg"),
               nfds = ffi.new("int[1]"),
               fds = ffi.new("int[?]", C.VHOST_USER_MEMORY_MAX_NREGIONS),
               listen_socket = socket,
               vring_base = {}
            }
   return setmetatable(o, {__index = VhostUser})
end

function VhostUser:pull ()
   if self.socket == nil then
      local res = C.vhost_user_accept(self.listen_socket)
      if res >= 0 then self.socket = res end
   else
      local msg = self.msg
      if C.vhost_user_receive(self.socket, msg, self.fds, self.nfds) > 0 then
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
   if self.rxring and self.txring then
--[[
      print("running")
      print("rx")
      print("desc[0].len", self.rxring.desc[0].len)
      print("avail.idx", self.rxring.avail.idx)
      print("used.idx", self.rxring.used.idx)
      print("tx")
      print("desc[0].len", self.txring.desc[0].len)
      print("avail.idx", self.txring.avail.idx)
      print("used.idx", self.txring.used.idx)
--]]
      while self.rxavail ~= self.rxring.avail.idx do
         local descriptor_index = self.rxring.avail.ring[self.rxavail % self.vring_num]
         local descriptor = self.rxring.desc[descriptor_index]
         local guest_addr = descriptor.addr
         local snabb_addr = map_from_guest(guest_addr, self.mem_table)
         print(ptr(guest_addr), ptr(snabb_addr))
         local len = descriptor.len
         io.write(("received %d byte packet: "):format(len))
         local p = ffi.cast("char*", snabb_addr)
         for i = 0, 13 do
            io.write(string.format("%02X ", p[i]))
         end
         io.write("\n")
         self.rxavail = (self.rxavail + 1) % 65536
      end
      -- Receive from virtio vring
      -- Kick virtio vring if needed
   end
end

function VhostUser:receive ()
   
end

function VhostUser:push ()
   -- Transmit to virtio vring

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
   print("call["..idx.."] = " .. fds[0])
end

function VhostUser:set_vring_kick (msg, fds, nfds)
   local idx = msg.file.index
   assert(idx < 42)
   assert(nfds == 1)
   print("kick["..idx.."] = " .. fds[0])
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
   else
      self.rxring = ring
      self.rxavail = 0
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
      table.insert(self.mem_table, { guest = guest,
                                     snabb = ffi.cast("int64_t", pointer),
                                     size  = tonumber(size) })
      print("mapping", ptr(pointer), ptr(guest), size)
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
   print("mapping from guest", ptr(addr))
   print("#mem_table", #mem_table)
   for _,m in ipairs(mem_table) do
      print(ptr(addr), "guest:", ptr(m.guest), "snabb:", ptr(m.snabb))
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
   app.apps.vhost_user = app.new(VhostUser:new("/home/luke/qemu.sock"))
--   app.apps.vhost_user = app.new(VhostUser:new("vapp.sock"))
   app.relink()
   local deadline = lib.timer(1e15)
   repeat
      app.breathe()
      C.usleep(1e5)
   until false
end


function ptr (x) return ffi.cast("void*",x) end
