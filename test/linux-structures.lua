-- test Linux structures against standard headers

--[[
luajit test/linux-structures.lua x64 > ./obj/s.c && cc -U__i386__ -I./include/linux-kernel-headers/x86_64/include -o ./obj/s ./obj/s.c && ./obj/s
]]

local abi = require "syscall.abi"

if arg[1] then -- fake arch
  abi.arch = arg[1]
  if abi.arch == "x64" then abi.abi32, abi.abi64 = false, true else abi.abi32, abi.abi64 = true, false end
  if abi.arch == "mips" then abi.mipsabi = "o32" end
end

local function fixup_structs(abi, ctypes)

  if abi.abi32 then
    ctypes["struct stat64"], ctypes["struct stat"] = ctypes["struct stat"], nil
  end

  ctypes["struct ktermios"], ctypes["struct termios"] = ctypes["struct termios"], nil

  -- internal only
  ctypes["struct capabilities"] = nil
  ctypes["struct cap"] = nil
  ctypes["struct {dev_t dev;}"] = nil

  -- standard headers use __kernel types for these or just fixed sizes
  ctypes.ino_t = nil
  ctypes.blkcnt_t = nil
  ctypes.dev_t = nil
  ctypes.in_port_t = nil
  ctypes.id_t = nil
  ctypes.time_t = nil
  ctypes.daddr_t = nil
  ctypes.clockid_t = nil
  ctypes.socklen_t = nil
  ctypes.uid_t = nil
  ctypes.gid_t = nil
  ctypes.pid_t = nil
  ctypes.nlink_t = nil
  ctypes.clock_t = nil
  ctypes.mode_t = nil
  ctypes.nfds_t = nil
  ctypes.blksize_t = nil

  -- misc issues
  ctypes["struct user_cap_data"] = nil -- defined as __user_cap_data_struct in new uapi headers, not in old ones at all
  ctypes["fd_set"] = nil -- just a pointer for the kernel, you define size
  ctypes["struct sched_param"] = nil -- not defined in our headers yet
  ctypes["struct udphdr"] = nil -- not a kernel define
  ctypes["struct seccomp_data"] = nil -- not defined yet
  ctypes["struct ucred"] = nil -- not defined yet
  ctypes["struct msghdr"] = nil -- not defined
  ctypes.mcontext_t = nil -- not defined
  ctypes.ucontext_t = nil -- not defined
  ctypes.sighandler_t = nil -- not defined
  ctypes["struct utsname"] = nil -- not defined
  ctypes["struct linux_dirent64"] = nil -- not defined
  ctypes["struct cpu_set_t"] = nil -- not defined
  ctypes["struct fdb_entry"] = nil -- not defined
  ctypes["struct user_cap_header"] = nil -- not defined
  ctypes["struct sockaddr_storage"] = nil -- uses __kernel_

  return ctypes
end

-- not defined by kernel
print [[
#include <stdint.h>
#include <stdio.h>
#include <stddef.h>

typedef unsigned short int sa_family_t;

struct sockaddr {
  sa_family_t sa_family;
  char sa_data[14];
};
]]

print [[
#include <linux/types.h>
#include <linux/stddef.h>
#include <linux/unistd.h>
#include <linux/net.h>
#include <linux/uio.h>
#include <linux/socket.h>
#include <linux/poll.h>
#include <linux/eventpoll.h>
#include <linux/signal.h>
#include <linux/ip.h>
#include <linux/in.h>
#include <linux/un.h>
#include <linux/in6.h>
#include <linux/capability.h>
#include <linux/reboot.h>
#include <linux/falloc.h>
#include <linux/mman.h>
#include <linux/veth.h>
#include <linux/sockios.h>
#include <linux/sched.h>
#include <linux/posix_types.h>
#include <linux/if.h>
#include <linux/if_bridge.h>
#include <linux/if_tun.h>
#include <linux/if_arp.h>
#include <linux/if_link.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <linux/ioctl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/netfilter.h>
#include <linux/netfilter/x_tables.h>
#include <linux/netfilter_ipv4/ip_tables.h>
#include <linux/vhost.h>
#include <linux/neighbour.h>
#include <linux/prctl.h>
#include <linux/fcntl.h>
#include <linux/timex.h>
#include <linux/aio_abi.h>
#include <linux/fs.h>
#include <linux/wait.h>
#include <linux/resource.h>
#include <linux/termios.h>
#include <linux/xattr.h>
#include <linux/stat.h>
#include <linux/fadvise.h>
#include <linux/inotify.h>
#include <linux/route.h>
#include <linux/ipv6_route.h>
#include <linux/neighbour.h>
#include <linux/errno.h>
#include <linux/signalfd.h>
#include <linux/mqueue.h>
#include <linux/virtio_pci.h>
#include <linux/pci.h>
//#include <linux/vfio.h>
//#include <linux/seccomp.h>

#include <asm/statfs.h>
#include <asm/stat.h>
#include <asm/termbits.h>

int ret;

void sassert(int a, int b, char *n) {
  if (a != b) {
    printf("error with %s: %d (0x%x) != %d (0x%x)\n", n, a, a, b, b);
    ret = 1;
  }
}

void sassert_u64(uint64_t a, uint64_t b, char *n) {
  if (a != b) {
    printf("error with %s: %llu (0x%llx) != %llu (0x%llx)\n", n, (unsigned long long)a, (unsigned long long)a, (unsigned long long)b, (unsigned long long)b);
    ret = 1;
  }
}

int main(int argc, char **argv) {
]]

local ffi = require "ffi"

local reflect = require "include.ffi-reflect.reflect"

local S = require "syscall"
local ctypes = S.types.ctypes

ctypes = fixup_structs(abi, ctypes)

-- TODO fix
local ignore_offsets = {
  st_atime_nsec = true, -- stat
  st_ctime_nsec = true, -- stat
  st_mtime_nsec = true, -- stat
  val = true, -- sigset_t, I think renamed
  ihl = true, -- bitfield
  version = true, -- bitfield
}

-- iterate over S.ctypes
for k, v in pairs(ctypes) do
  -- check size
  print("sassert(sizeof(" .. k .. "), " .. ffi.sizeof(v) .. ', "' .. k .. '");')
  -- check offset of struct fields
  local refct = reflect.typeof(v)
  if refct.what == "struct" then
    for r in refct:members() do
      local name = r.name
      -- bit hacky - TODO fix these issues
      if not name or ignore_offsets[name] or name:sub(1,2) == "__" then name = nil end
      if name then
        print("sassert(offsetof(" .. k .. "," .. name .. "), " .. ffi.offsetof(v, name) .. ', " offset of ' .. name .. ' in ' .. k .. '");')
      end
    end
  end
end

print [[
return ret;
}
]]


