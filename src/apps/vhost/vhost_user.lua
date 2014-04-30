--
-- See http://www.virtualopensystems.com/en/solutions/guides/snabbswitch-qemu/

module(...,package.seeall)

local basic_apps= require("apps.basic.basic_apps")
local pcap      = require("apps.pcap.pcap")
local app       = require("core.app")
local buffer    = require("core.buffer")
local config    = require("core.config")
local link      = require("core.link")
local main      = require("core.main")
local pci       = require("lib.hardware.pci")
local net_device= require("lib.virtio.net_device")
local timer     = require("core.timer")
local ffi       = require("ffi")
local C         = ffi.C

require("apps.vhost.vhost_h")
require("apps.vhost.vhost_user_h")

assert(ffi.sizeof("struct vhost_user_msg") == 212, "ABI error")

VhostUser = {}

function VhostUser:new (socket_path)
   local o = { state = 'init',
      dev = nil,
      msg = ffi.new("struct vhost_user_msg"),
      nfds = ffi.new("int[1]"),
      fds = ffi.new("int[?]", C.VHOST_USER_MEMORY_MAX_NREGIONS),
      socket_path = socket_path,
      -- process qemu messages delay counter
      process_qemu_counter = 0
   }
   self = setmetatable(o, {__index = VhostUser})
   self.dev = net_device.VirtioNetDevice:new(self)
   return self
end

function VhostUser:pull ()
   if not self.connected then
      self:connect()
   else
      self:process_qemu_requests()
      if self.vhost_ready then
         self.dev:poll_vring_packets()
      end
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
   [C.VHOST_USER_SET_VRING_ERR]   = 'set_vring_err'
}

-- Process all vhost_user requests from QEMU.
function VhostUser:process_qemu_requests ()
   self.process_qemu_counter = self.process_qemu_counter + 1
   if self.vhost_ready and self.process_qemu_counter % 1000000 ~= 0 then return end

   local msg = self.msg
   local stop = false

   repeat
      local ret = C.vhost_user_receive(self.socket, msg, self.fds, self.nfds)

      if ret > 0 then
         assert(msg.request >= 0 and msg.request <= C.VHOST_USER_MAX)
         debug("Got vhost_user request", handler_names[msg.request], msg.request)
         local method = self[handler_names[msg.request]]
         if method then
            method(self, msg, self.fds, self.nfds[0])
         else
            error(string.format("vhost_user unrecognized request: %d", msg.request))
         end
         msg.request = -1;
      else
         stop = true
         if ret == 0 then
            print ("Connection went down")
            self.socket = -1
            self.connected = false
            self.vhost_ready = false
            if self.link_down_proc then self.link_down_proc() end
         end
      end
   until stop

end

function VhostUser:none (msg)
   error(string.format("vhost_user unrecognized request: %d", msg.request))
end

function VhostUser:get_features (msg)
   msg.u64 = self.dev:get_features()
   msg.size = ffi.sizeof("uint64_t")
   -- In future add TSO4/TSO6/UFO/ECN and control channel
   self:reply(msg)
end

function VhostUser:set_features (msg)
   self.dev:set_features(msg.u64)
end

function VhostUser:set_owner (msg)
   debug("set_owner")
end

function VhostUser:reset_owner (msg)
   debug("reset_owner")
end

function VhostUser:set_vring_num (msg)
   self.dev:set_vring_num(msg.state.index, msg.state.num)
end

function VhostUser:set_vring_call (msg, fds, nfds)
   local idx = tonumber(bit.band(msg.u64, C.VHOST_USER_VRING_IDX_MASK))
   local validfd = bit.band(msg.u64, C.VHOST_USER_VRING_NOFD_MASK) == 0

   assert(idx<42)
   if validfd then
      assert(nfds == 1)
      self.dev:set_vring_call(idx, fds[0])
   end
end

function VhostUser:set_vring_kick (msg, fds, nfds)
   local idx = tonumber(bit.band(msg.u64, C.VHOST_USER_VRING_IDX_MASK))
   local validfd = bit.band(msg.u64, C.VHOST_USER_VRING_NOFD_MASK) == 0

   assert(idx < 42)
   if validfd then
      assert(nfds == 1)
      self.dev:set_vring_kick(idx, fds[0])
   else
      print("Should start polling on virtq "..tonum(idx))
   end
end

function VhostUser:set_vring_addr (msg)
   local desc  = self.dev:map_from_qemu(msg.addr.desc_user_addr)
   local used  = self.dev:map_from_qemu(msg.addr.used_user_addr)
   local avail = self.dev:map_from_qemu(msg.addr.avail_user_addr)
   local ring = { desc  = ffi.cast("struct vring_desc *", desc),
      used  = ffi.cast("struct vring_used *", used),
      avail = ffi.cast("struct vring_avail *", avail) }

   self.dev:set_vring_addr(msg.addr.index, ring)

   if self.dev:ready() then
      self.vhost_ready = true
      self.dev:set_virtio_device_id(buffer.add_virtio_device(self.dev))
      debug("Connected and initialized vhost_user.")
   end
end

function VhostUser:set_vring_base (msg)
   debug("set_vring_base", msg.state.index, msg.state.num)
   self.dev:set_vring_base(msg.state.index, msg.state.num)
end

function VhostUser:get_vring_base (msg)
   msg.state.num = self.dev:get_vring_base(msg.state.index)
   msg.size = ffi.sizeof("struct vhost_vring_state")
   self:reply(msg)
end

function VhostUser:set_mem_table (msg, fds, nfds)
   mem_table = {}
   assert(nfds == msg.memory.nregions)
   for i = 0, msg.memory.nregions - 1 do
      assert(fds[i] > 0) -- XXX vapp_server.c uses 'if'
      local size = msg.memory.regions[i].memory_size
      local pointer = C.vhost_user_map_guest_memory(fds[i], size)
      -- XXX Find a more elegant way to map this as IO memory.
      C.mmap_memory(pointer, size, ffi.cast("uint64_t",pointer), true, true)
      local guest = msg.memory.regions[i].guest_phys_addr
      local qemu = msg.memory.regions[i].userspace_addr
      table.insert(mem_table, { guest = guest,
         qemu  = qemu,
         snabb = ffi.cast("int64_t", pointer),
         size  = tonumber(size) })
   end
   self.dev:set_mem_table(mem_table)
end

function VhostUser:reply (req)
   assert(self.socket)
   req.flags = 5
   C.vhost_user_send(self.socket, req)
end

function VhostUser:report()
   self.dev:report()
end

function VhostUser:rx_buffers()
   return self.dev:rx_buffers()
end

function selftest ()
   print("selftest: vhost_user")
   -- Create an app network that proxies packets between a vhost_user
   -- port (qemu) and a sink. Create
   -- separate pcap traces for packets received from vhost.
   --
   -- schema for traffic from the VM:
   --
   -- vhost -> tee -> sink
   --           |
   --           v
   --       vhost pcap
   --

   local vhost_user_sock = os.getenv("SNABB_TEST_VHOST_USER_SOCKET")
   if not vhost_user_sock then
      print("SNABB_TEST_VHOST_USER_SOCKET was not set\nTest skipped")
      os.exit(app.test_skipped_code)
   end
   local c = config.new()
   config.app(c, "vhost_user", VhostUser, vhost_user_sock)
   --config.app(c, "vhost_dump", pcap.PcapWriter, "vhost_vm_dump.cap")
   config.app(c, "vhost_tee", basic_apps.Tee)
   config.app(c, "sink", basic_apps.Sink)
   config.app(c, "source", basic_apps.Source, "250")
   config.app(c, "source_tee", basic_apps.Tee)

   config.link(c, "vhost_user.tx -> vhost_tee.input")
   --config.link(c, "vhost_tee.dump -> vhost_dump.input")
   config.link(c, "vhost_tee.traffic -> sink.in")

   config.link(c, "source.tx -> source_tee.input")
   config.link(c, "source_tee.traffic -> vhost_user.rx")

   app.configure(c)
   local vhost_user = app.app_table.vhost_user
   vhost_user.link_down_proc = function()
      main.exit(0)
   end
   local source = app.app_table.source
   source:set_rx_buffer_freelist(vhost_user:rx_buffers())

   local fn = function ()
      local vu = app.apps.vhost_user
      app.report()
      if vhost_user.vhost_ready then
         vhost_user:report()
      end
   end
   timer.init()
   timer.activate(timer.new("report", fn, 10e9, 'repeating'))

   app.main()
end

function ptr (x) return ffi.cast("void*",x) end

function debug (...)
   print(...)
end

