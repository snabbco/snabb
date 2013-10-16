-- test just the constants for Linux, against standard set so cross platform.
-- test against make headers_install ARCH=i386 INSTALL_HDR_PATH=/tmp
-- fix linux/input.h includes which are broken
-- luajit test/linux-constants.lua > /tmp/c.c && cc -I/tmp/include  -o /tmp/c /tmp/c.c && /tmp/c

-- TODO fix up so can test all architectures
-- TODO 32 bit warnings about signed ranges

local function fixup(abi, c)
  -- we only use one set
  if abi.abi64 then
    c.F.GETLK64   = nil
    c.F.SETLK64   = nil
    c.F.SETLKW64  = nil
  else
    c.F.GETLK     = nil
    c.F.SETLK     = nil
    c.F.SETLKW    = nil
  end

  -- internal use
  c.syscall = nil
  c.OMQATTR = nil

  -- misleading, Musl has higher than Linux
  c.HOST_NAME_MAX = nil

  -- fake constants
  c.MS.RO = nil
  c.MS.RW = nil
  c.MS.SECLABEL = nil
  c.IFF.ALL = nil
  c.IFF.NONE = nil
  c.W.ALL = nil
  c.MAP.ANON = nil -- MAP.ANONYMOUS only

  -- oddities to fix
  c.IFLA_VF_INFO.INFO = nil
  c.IFLA_VF_PORT.PORT = nil

  -- umount is odd
  c.MNT = {}
  c.MNT.FORCE = c.UMOUNT.FORCE
  c.MNT.DETACH = c.UMOUNT.DETACH
  c.MNT.EXPIRE = c.UMOUNT.EXPIRE
  c.UMOUNT.FORCE = nil
  c.UMOUNT.DETACH = nil
  c.UMOUNT.EXPIRE = nil

  if abi.abi64 then c.O.LARGEFILE = nil end

  -- renamed constants
  c.OPIPE = nil

  -- we renamed these for namespacing reasons TODO can just set in nm table
  for k, v in pairs(c.IFREQ) do c.IFF[k] = v end
  c.IFREQ = nil

  c.__WNOTHREAD = c.W.NOTHREAD
  c.__WALL = c.W.ALL
  c.__WCLONE = c.W.CLONE
  c.W.NOTHREAD, c.W.ALL, c.W.CLONE = nil, nil, nil

  -- not part of kernel ABI I think - TODO check and maybe remove from ljsyscall
  c.SOMAXCONN = nil
  c.E.NOTSUP = nil
  c.SIG.CLD = nil

  -- extra friendly names
  c.WAIT.ANY = nil
  c.WAIT.MYPGRP = nil

  -- surely part of ABI? not defined in kernel ones we have though
  c.AF = nil
  c.MSG = nil
  c.SOCK = nil
  c.SOL = nil
  c.SHUT = nil
  c.OK = nil
  c.DT = nil

  -- part of man(3) API so we can use any value we like?? - TODO move to common code? is this true in all OSs
  c.LOCKF = nil
  c.STD = nil
  c.SCM = nil
  c.TCSA = nil
  c.TCFLUSH = nil
  c.TCFLOW = nil
  c.EXIT = nil

  -- not defined?
  c.UTIME = nil
  c.REG = nil
  c.PC = nil -- neither _PC or _POSIX_ defined for capabilities

  -- pointer type
  c.SIGACT = nil

  -- epoll uses POLL values internally? 
  c.EPOLL.MSG = nil
  c.EPOLL.WRBAND = nil
  c.EPOLL.RDHUP = nil
  c.EPOLL.WRNORM = nil
  c.EPOLL.RDNORM = nil
  c.EPOLL.HUP = nil
  c.EPOLL.ERR = nil
  c.EPOLL.RDBAND = nil
  c.EPOLL.IN = nil
  c.EPOLL.OUT = nil
  c.EPOLL.PRI = nil

  -- only in very recent headers, not in ones we are testing against, but include seccomp - will upgrade headers or fix soon
  c.IPPROTO.TP = nil
  c.IPPROTO.MTP = nil
  c.IPPROTO.ENCAP = nil
  c.SO.PEEK_OFF = nil
  c.SO.GET_FILTER = nil
  c.SO.NOFCS = nil
  c.IFF.DETACH_QUEUE = nil
  c.IFF.ATTACH_QUEUE = nil
  c.IFF.MULTI_QUEUE = nil
  c.PR.SET_NO_NEW_PRIVS = nil
  c.PR.GET_NO_NEW_PRIVS = nil
  c.PR.GET_TID_ADDRESS = nil
  c.TUN.TAP_MQ = nil
  c.IP.UNICAST_IF = nil
  c.NTF.SELF = nil
  c.NTF.MASTER = nil
  c.SECCOMP_MODE = nil
  c.SECCOMP_RET = nil

  -- these are not even in linux git head headers or names wrong
  c.O.ASYNC = nil
  c.O.FSYNC = nil
  c.O.RSYNC = nil
  c.SPLICE_F = nil -- not in any exported header, there should be a linux/splice.h for userspace
  c.MNT.FORCE = nil
  c.MNT.EXPIRE = nil
  c.MNT.DETACH = nil
  c.EPOLLCREATE.NONBLOCK = nil
  c.PR_MCE_KILL_OPT = nil
  c.SWAP_FLAG = nil
  c.ETHERTYPE = nil
  c.TFD = nil
  c.UMOUNT.NOFOLLOW = nil
  c.EFD = nil
  c.SCHED.OTHER = nil
  c.AT_ACCESSAT.EACCESS = nil
  c.SI.ASYNCNL = nil
  c.RLIMIT.OFILE = nil
  c.TFD_TIMER.ABSTIME = nil

  -- renamed it seems, TODO sort out
  c.SYS.newfstatat = c.SYS.fstatat
  c.SYS.fstatat = nil

  -- also renamed/issues on arm TODO sort out
  if abi.arch == "arm" then
    c.SYS.fadvise64_64 = nil
    c.SYS.sync_file_range = nil
  end

  return c
end

local nm = {
  E = "E",
  SIG = "SIG",
  EPOLL = "EPOLL",
  STD = "STD",
  MODE = "S_I",
  MSYNC = "MS_",
  W = "W",
  POLL = "POLL",
  S_I = "S_I",
  LFLAG = "",
  IFLAG = "",
  OFLAG = "",
  CFLAG = "",
  CC = "",
  IOCTL = "",
  B = "B",
  SYS = "__NR_",
  FCNTL_LOCK = "F_",
  PC = "_PC_",
  AT_FDCWD = "AT_",
  AT_REMOVEDIR = "AT_",
  AT_SYMLINK_FOLLOW = "AT_",
  AT_SYMLINK_NOFOLLOW = "AT_",
  AT_ACCESSAT = "AT_",
  AT_FSTATAT = "AT_",
  SIGACT = "SIG_",
  SIGPM = "SIG_",
  SIGILL = "ILL_",
  SIGFPR = "FPE_",
  SIGSEGV = "SEGV_",
  SIGBUS = "BUS_",
  SIGTRAP = "TRAP_",
  SIGCLD = "CLD_",
  SIGPOLL = "POLL_",
  SIGFPE = "FPE_",
  IN_INIT = "IN_",
  LINUX_CAPABILITY_VERSION = "_LINUX_CAPABILITY_VERSION_",
  LINUX_CAPABILITY_U32S = "_LINUX_CAPABILITY_U32S_",
  EPOLLCREATE = "EPOLL_",
  RLIM = "RLIM64_",
}

-- not defined by kernel
print [[
#include <stdint.h>
#include <stdio.h>

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
#include <linux/socket.h>
#include <linux/poll.h>
#include <linux/eventpoll.h>
#include <linux/signal.h>
#include <linux/ip.h>
#include <linux/in.h>
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
#include <linux/virtio_pci.h>
//#include <linux/vfio.h>
//#include <linux/seccomp.h>

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

local abi = require "syscall.abi"

local ffi = require "ffi"

local c = require "syscall.linux.constants"

c = fixup(abi, c)

for k, v in pairs(c) do
  if type(v) == "number" then
    print("sassert(" .. k .. ", " .. v .. ', "' .. k .. '");')
  elseif type(v) == "table" then
    for k2, v2 in pairs(v) do
      local name = nm[k] or k .. "_"
      if type(v2) ~= "function" then
        if type(v2) == "cdata" and ffi.sizeof(v2) == 8 then -- TODO avoid use of ffi if possible
         print("sassert_u64(" .. name .. k2 .. ", " .. tostring(v2)  .. ', "' .. name .. k2 .. '");')
        else
         print("sassert(" .. name .. k2 .. ", " .. tostring(v2)  .. ', "' .. name .. k2 .. '");')
        end
      end
    end
  end
end

print [[
return ret;
}
]]

