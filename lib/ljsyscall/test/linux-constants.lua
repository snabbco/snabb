-- test against clean set of kernel headers, standard set so cross platform.

--[[
luajit test/linux-constants.lua x64 > ./obj/c.c && cc -U__i386__ -DBITS_PER_LONG=64 -I./include/linux-kernel-headers/x86_64/include -o ./obj/c ./obj/c.c && ./obj/c
luajit test/linux-constants.lua x86 > ./obj/c.c && cc -D__i386__ -DBITS_PER_LONG=32 -I./include/linux-kernel-headers/i386/include -o ./obj/c ./obj/c.c && ./obj/c
luajit test/linux-constants.lua arm > ./obj/c.c && cc -D__ARM_EABI__ -DBITS_PER_LONG=32 -I./include/linux-kernel-headers/arm/include -o ./obj/c ./obj/c.c && ./obj/c
luajit test/linux-constants.lua ppc > ./obj/c.c && cc -I./include/linux-kernel-headers/powerpc/include -o ./obj/c ./obj/c.c && ./obj/c
luajit test/linux-constants.lua mips > ./obj/c.c && cc -D__MIPSEL__ -D_MIPS_SIM=_MIPS_SIM_ABI32 -DCONFIG_32BIT -DBITS_PER_LONG=32 -D__LITTLE_ENDIAN_BITFIELD -D__LITTLE_ENDIAN -DCONFIG_CPU_LITTLE_ENDIAN -I./include/linux-kernel-headers/mips/include  -o ./obj/c ./obj/c.c && ./obj/c

]]

-- TODO 32 bit warnings about signed ranges

local abi = require "syscall.abi"

if arg[1] then -- fake arch
  abi.arch = arg[1]
  if abi.arch == "x64" then abi.abi32, abi.abi64 = false, true else abi.abi32, abi.abi64 = true, false end
  if abi.arch == "mips" then abi.mipsabi = "o32" end
end

local function fixup_constants(abi, c)
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
  c.errornames = nil
  c.OMQATTR = nil
  c.EALIAS = nil

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

  -- recent additions
  c.TCP.THIN_DUPACK = nil
  c.TCP.FASTOPEN = nil
  c.TCP.REPAIR_OPTIONS = nil
  c.TCP.THIN_LINEAR_TIMEOUTS = nil
  c.TCP.REPAIR = nil
  c.TCP.QUEUE_SEQ = nil
  c.TCP.TIMESTAMP = nil
  c.TCP.USER_TIMEOUT = nil
  c.TCP.REPAIR_QUEUE = nil

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
  c.MFD = nil
  c.RTA.NEWDST = nil
  c.RTA.PREF = nil
  c.RTA.VIA = nil
  c.RTA.MFC_STATS = nil
  c.AUDIT_ARCH.AARCH64 = nil
  c.SO.MAX_PACING_RATE = nil
  c.SO.BPF_EXTENSIONS = nil
  c.SO.INCOMING_CPU = nil
  c.SO.ATTACH_BPF = nil
  c.SO.DETACH_BPF = nil
  c.SO.ATTACH_REUSEPORT_CBPF = nil
  c.SO.ATTACH_REUSEPORT_EBPF = nil
  c.F_SEAL = nil
  c.F.ADD_SEALS = nil
  c.F.GET_SEALS = nil

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
  c.AT.EACCESS = nil
  c.SI.ASYNCNL = nil
  c.RLIMIT.OFILE = nil
  c.TFD_TIMER.ABSTIME = nil
  c.TFD_TIMER.CANCEL_ON_SET = nil
  c.AT.EMPTY_PATH = nil

  -- renamed it seems, TODO sort out
  c.SYS.newfstatat, c.SYS.fstatat = c.SYS.fstatat, nil

  -- also renamed/issues on arm TODO sort out
  if abi.arch == "arm" then
    c.SYS.fadvise64_64 = nil
    c.SYS.sync_file_range = nil
  end

  if abi.arch == "mips" then
     c.SYS._newselect, c.SYS.select = c.SYS.select, nil -- now called _newselect
  end

  -- new syscalls not in headers yet
  c.SYS.kcmp = nil
  c.SYS.finit_module = nil
  c.SYS.sched_setattr = nil
  c.SYS.sched_getattr = nil
  c.SYS.renameat2 = nil
  c.SYS.seccomp = nil
  c.SYS.getrandom = nil
  c.SYS.memfd_create = nil
  c.SYS.kexec_file_load = nil
  c.SYS.bpf = nil

  -- new constants
  c.GRND = nil
  -- requires Linux 3.19+, not supported on Travis
  c.BPF_MAP = {}
  c.BPF_CMD = {}
  c.BPF_PROG = {}
  c.BPF_ATTACH_TYPE = {}
  c.BPF.ALU64 = nil
  c.BPF.DW = nil
  c.BPF.JSGT = nil
  c.BPF.JSGE = nil
  c.BPF.CALL = nil
  c.BPF.EXIT = nil
  c.BPF.TO_LE = nil
  c.BPF.TO_BE = nil
  c.BPF.END = nil
  c.BPF.ARSH = nil
  c.BPF.XADD = nil
  c.BPF.JNE = nil
  c.BPF.MOV = nil
  c.BPF.ANY = nil
  c.BPF.EXIST = nil
  c.BPF.NOEXIST = nil
  -- no perf_event_open on Travis CI
  c.PERF_TYPE = {}
  c.PERF_COUNT = {}
  c.PERF_SAMPLE = {}
  c.PERF_FLAG = {}
  c.PERF_SAMPLE_REGS = {}
  c.PERF_SAMPLE_BRANCH = {}
  c.PERF_READ_FORMAT = {}
  c.PERF_RECORD = {}

  c.SOF.TIMESTAMPING_LAST = nil
  c.SOF.TIMESTAMPING_MASK = nil
  c.SOF.TIMESTAMPING_OPT_CMSG = nil
  c.SOF.TIMESTAMPING_OPT_ID = nil
  c.SOF.TIMESTAMPING_OPT_PKTINFO = nil
  c.SOF.TIMESTAMPING_OPT_STATS = nil
  c.SOF.TIMESTAMPING_OPT_TSONLY = nil
  c.SOF.TIMESTAMPING_OPT_TX_SWHW = nil
  c.SOF.TIMESTAMPING_RAW_HARDWARE = nil
  c.SOF.TIMESTAMPING_RX_HARDWARE = nil
  c.SOF.TIMESTAMPING_RX_SOFTWARE = nil
  c.SOF.TIMESTAMPING_SOFTWARE = nil
  c.SOF.TIMESTAMPING_SYS_HARDWARE = nil
  c.SOF.TIMESTAMPING_TX_ACK = nil
  c.SOF.TIMESTAMPING_TX_HARDWARE = nil
  c.SOF.TIMESTAMPING_TX_SCHED = nil
  c.SOF.TIMESTAMPING_TX_SOFTWARE = nil

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
#include <linux/pci.h>
#include <linux/tcp.h>
#include <linux/vfio.h>
#include <linux/seccomp.h>

/* defined in attr/xattr.h */
#define ENOATTR ENODATA

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

local c = require "syscall.linux.constants"

local nr = require("syscall.linux.nr")

c.SYS = nr.SYS -- add syscalls

c = fixup_constants(abi, c)

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

