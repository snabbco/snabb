module(...,package.seeall)

local app    = require("core.app")
local lib    = require("core.lib")
local ffi = require("ffi")
local C   = ffi.C

require("lib.virtio.virtio_vring_h")
require("apps.vhost.vhost_h")
require("apps.vhost.vhost_user_h")

VhostUser = {}

function VhostUser:new (socket_path)
   local socket = C.vhost_user_open_socket(socket_path)
   assert(socket >= 0, "failed to open socket: " .. socket_path)
   local o = { state = 'init',
               msg = ffi.new("struct vhost_user_msg"),
               listen_socket = socket,
               -- Virtio state
               vring_rx = false,
               vring_tx = false,
               kickfd = false,
               callfd = false
            }
   return setmetatable(o, {__index = VhostUser})
end

function VhostUser:pull ()
   print("pull")
   if self.socket == nil then
      local res = C.vhost_user_accept(self.listen_socket)
      if res >= 0 then self.socket = res end
   else
      local msg = self.msg
      if C.vhost_user_receive(self.socket, msg) > 0 then
         assert(msg.request >= 0 and msg.request <= C.VHOST_USER_MAX)
         local method = self[handler_names[msg.request]]
         if method then
            method(self, msg)
         else
            print(msg.request, C.VHOST_USER_GET_FEATURES)
            print("vhost_user: no handler for " .. handler_names[msg.request])
         end
      end
      -- Receive from virtio vring
      
      -- Kick virtio vring if needed
   end
end

function VhostUser:push ()
   -- Transmit to virtio vring

end

-- Handler functions for each request type

-- Table of request code -> name of handler method
handler_names = {
   [C.VHOST_USER_NONE]            = 'handle_none',
   [C.VHOST_USER_GET_FEATURES]    = 'handle_get_features',
   [C.VHOST_USER_SET_FEATURES]    = 'handle_set_features',
   [C.VHOST_USER_SET_OWNER]       = 'handle_set_owner',
   [C.VHOST_USER_RESET_OWNER]     = 'handle_reset_owner',
   [C.VHOST_USER_SET_MEM_TABLE]   = 'handle_set_mem_table',
   [C.VHOST_USER_SET_LOG_BASE]    = 'handle_set_log_base',
   [C.VHOST_USER_SET_LOG_FD]      = 'handle_set_log_fd',
   [C.VHOST_USER_SET_VRING_NUM]   = 'handle_set_vring_num',
   [C.VHOST_USER_SET_VRING_ADDR]  = 'handle_set_vring_addr',
   [C.VHOST_USER_SET_VRING_BASE]  = 'handle_set_vring_base',
   [C.VHOST_USER_GET_VRING_BASE]  = 'handle_get_vring_base',
   [C.VHOST_USER_SET_VRING_KICK]  = 'handle_set_vring_kick',
   [C.VHOST_USER_SET_VRING_CALL]  = 'handle_set_vring_call',
   [C.VHOST_USER_SET_VRING_ERR]   = 'handle_set_vring_err',
   [C.VHOST_USER_NET_SET_BACKEND] = 'handle_net_set_backend'
}

function selftest ()
   print("selftest: vhost_user")
   app.apps.vhost_user = app.new(VhostUser:new("vapp.sock"))
   app.relink()
   local deadline = lib.timer(1e11)
   repeat
      app.breathe()
      C.usleep(1e6)
   until deadline()
end


