-- x64 specific definitions

local ffi = require "ffi"

local arch = {}

arch.epoll = function()
ffi.cdef[[
struct epoll_event {
  uint32_t events;      /* Epoll events */
  epoll_data_t data;    /* User data variable */
}  __attribute__ ((packed));
]]
end

return arch

