module(...,package.seeall)

local ffi = require("ffi")
local C   = ffi.C

VhostUser = {}

function VhostUser:new (socket_path)
   local socket = C.vhost_user_open_socket(socket_path)
   assert(socket >= 0, "failed to open socket: " .. socket_path)
   local o = { state = 'init',
               msg = ffi.new("struct vhost_user_msg")
               socket = socket
               -- Virtio state
               vring_rx = ...
               vring_tx = ...
               kickfd = ...
               callfd = ...

            }
   return setmetatable(o, {__index__ = VhostUser})
end

function VhostUser:pull ()
   -- Handle Unix socket
   if C.vhost_user_receive(self.socket, self.msg) > 0 then
      assert(msg.request >= 0 and msg.request <= VHOST_USER_MAX)
      local handler = handlers[msg.request]
      handlers[msg.request](self, msg)
   end
   -- Receive from virtio vring
   ...
   -- Kick virtio vring if needed
end

function VhostUser:push ()
   -- Transmit to virtio vring
   ...
end

-- Handler functions for each request type

function VhostUser:handle_none (msg)
   ...
end

-- ...

-- Table of request code -> handler method
handlers = {
   C.VHOST_USER_NONE            = VhostUser.handle_none
   C.VHOST_USER_GET_FEATURES    = VhostUser.handle_get_features
   C.VHOST_USER_SET_FEATURES    = VhostUser.handle_set_features
   C.VHOST_USER_SET_OWNER       = VhostUser.handle_set_owner
   C.VHOST_USER_RESET_OWNER     = VhostUser.handle_reset_owner
   C.VHOST_USER_SET_MEM_TABLE   = VhostUser.handle_set_mem_table
   C.VHOST_USER_SET_LOG_BASE    = VhostUser.handle_set_log_base
   C.VHOST_USER_SET_LOG_FD      = VhostUser.handle_set_log_fd
   C.VHOST_USER_SET_VRING_NUM   = VhostUser.handle_set_vring_num
   C.VHOST_USER_SET_VRING_ADDR  = VhostUser.handle_set_vring_addr
   C.VHOST_USER_SET_VRING_BASE  = VhostUser.handle_set_vring_base
   C.VHOST_USER_GET_VRING_BASE  = VhostUser.handle_get_vring_base
   C.VHOST_USER_SET_VRING_KICK  = VhostUser.handle_set_vring_kick
   C.VHOST_USER_SET_VRING_CALL  = VhostUser.handle_set_vring_call
   C.VHOST_USER_SET_VRING_ERR   = VhostUser.handle_set_vring_err
   C.VHOST_USER_NET_SET_BACKEND = VhostUser.handle_net_set_backend
}

