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

-- packed to match x86
arch.statfs64 = function()
ffi.cdef[[
typedef long statfs_word;
struct statfs64 {
  statfs_word f_type;
  statfs_word f_bsize;
  uint64_t f_blocks;
  uint64_t f_bfree;
  uint64_t f_bavail;
  uint64_t f_files;
  uint64_t f_ffree;
  kernel_fsid_t f_fsid;
  statfs_word f_namelen;
  statfs_word f_frsize;
  statfs_word f_flags;
  statfs_word f_spare[4];
} __attribute__((packed,aligned(4)));
]]
end

return arch

