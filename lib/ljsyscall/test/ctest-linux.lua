-- generate C test file to check type sizes etc
-- Linux specific as there are a lot of workarounds
-- luajit ctest.lua > ctest.c && cc -std=c99 ctest.c -o ctest && ./ctest

-- TODO we are replacing this with new tests against clean kernel headers, test/linux-constants.lua is first part
-- however testing against both still useful, could be errors in clean set - headers are a mess.

local S = require "syscall"

local abi = S.abi
local types = S.types
local t, ctypes, s = types.t, types.ctypes, types.s
local c = S.c

local nr = require("syscall.linux.nr")

c.SYS = nr.SYS -- add syscalls

local ffi = require "ffi"

local reflect = require "include.ffi-reflect.reflect"

-- TODO fix these, various naming issues
ctypes["struct linux_dirent64"] = nil
ctypes["struct fdb_entry"] = nil
ctypes["sighandler_t"] = nil
ctypes["struct rlimit64"] = nil
ctypes["struct mq_attr"] = nil
ctypes["int errno"] = nil
ctypes["struct user_cap_header"] = nil
ctypes["struct user_cap_data"] = nil
ctypes["struct sched_param"] = nil -- libc truncates unused parts
ctypes["struct cpu_set_t"] = nil -- not actually a struct
ctypes["dev_t"] = nil -- use kernel value not glibc
ctypes["struct seccomp_data"] = nil -- not in ppc setup, remove for now
ctypes["sigset_t"] = nil -- use kernel value not glibc
ctypes["ucontext_t"] = nil -- as we use kernel sigset_t, ucontext differs too
ctypes["struct {dev_t dev;}"] = nil -- not a real type
ctypes["struct mmsghdr"] = nil -- not on Travis

if abi.abi32 then
  ctypes["struct stat64"], ctypes["struct stat"] = ctypes["struct stat"], nil
end

-- we do not use the ino_t and blkcnt_t types, they are really 64 bit
if abi.abi32 then
  ctypes.ino_t = nil
  ctypes.blkcnt_t = nil
end

-- internal only
ctypes["struct capabilities"] = nil
ctypes["struct cap"] = nil

-- TODO seems to be an issue with sockaddr_storage (alignment difference?) on Musl, needs fixing
ctypes["struct sockaddr_storage"] = nil
-- TODO seems to be a size issue on Musl, have asked list
ctypes["struct sysinfo"] = nil

-- size issue on Musl, incomplete type on glibc
ctypes["struct siginfo"] = nil

-- both glibc and Musl mess around with kernel sizes, larger so ok.
ctypes["struct termios"] = nil

-- not defined by glibc
ctypes["struct k_sigaction"] = nil

-- eBPF not available on Travis / opaque types
ctypes["struct bpf_insn"] = nil
ctypes["union bpf_attr"] = nil
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
c.BPF.ANY = nil
c.BPF.NOEXIST = nil
c.BPF.EXIST = nil
c.BPF.END = nil
c.BPF.ARSH = nil
c.BPF.XADD = nil
c.BPF.JNE = nil
c.BPF.MOV = nil
c.SYS.bpf = nil

-- no perf_event_open on Travis CI
ctypes["struct perf_event_attr"] = nil
ctypes["struct perf_event_reader"] = nil
ctypes["struct perf_event_header"] = nil
ctypes["struct perf_event_mmap_page"] = nil
c.PERF_TYPE = {}
c.PERF_COUNT = {}
c.PERF_SAMPLE = {}
c.PERF_FLAG = {}
c.PERF_SAMPLE_REGS = {}
c.PERF_SAMPLE_BRANCH = {}
c.PERF_READ_FORMAT = {}
c.PERF_RECORD = {}
-- no perf_event_open ioctls on Travis CI
c.IOCTL.PERF_EVENT_IOC_ENABLE = nil
c.IOCTL.PERF_EVENT_IOC_DISABLE = nil
c.IOCTL.PERF_EVENT_IOC_REFRESH = nil
c.IOCTL.PERF_EVENT_IOC_RESET = nil
c.IOCTL.PERF_EVENT_IOC_PERIOD = nil
c.IOCTL.PERF_EVENT_IOC_SET_OUTPUT = nil
c.IOCTL.PERF_EVENT_IOC_SET_FILTER = nil
c.IOCTL.PERF_EVENT_IOC_ID = nil
c.IOCTL.PERF_EVENT_IOC_SET_BPF = nil

-- not in kernel headers used by Travis CI
ctypes["struct scm_timestamping"] = nil
c.SCM.TSTAMP_ACK = nil
c.SCM.TSTAMP_SCHED = nil
c.SCM.TSTAMP_SND = nil
c.SCM.TIMESTAMPING_OPT_STATS = nil

-- not in kernel headers used by Travis CI
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

if abi.arch == "arm" then ctypes["struct statfs64"] = nil end -- padding difference, not that important

for k, v in pairs(c.IOCTL) do if type(v) == "table" then c.IOCTL[k] = v.number end end

-- internal use
c.syscall = nil
c.OMQATTR = nil
c.errornames = nil

-- fake constants
c.MS.RO = nil
c.MS.RW = nil
c.MS.SECLABEL = nil
c.IFF.ALL = nil
c.IFF.NONE = nil
c.W.ALL = nil

-- umount is odd
c.MNT = {}
c.MNT.FORCE = c.UMOUNT.FORCE
c.MNT.DETACH = c.UMOUNT.DETACH
c.MNT.EXPIRE = c.UMOUNT.EXPIRE
c.UMOUNT.FORCE = nil
c.UMOUNT.DETACH = nil
c.UMOUNT.EXPIRE = nil

-- renamed constants
c.O.NONBLOCK = c.OPIPE.NONBLOCK
c.O.CLOEXEC = c.OPIPE.CLOEXEC
c.OPIPE = nil

-- we renamed these for namespacing reasons
for k, v in pairs(c.IFREQ) do c.IFF[k] = v end
c.IFREQ = nil

-- TODO find the headers/flags for these if exist, or remove
c.SA.RESTORER = nil
c.AF.DECNET = nil
c.SIG.HOLD = nil
c.NOTHREAD = nil
c.RTF.PREFIX_RT = nil
c.RTF.EXPIRES = nil
c.RTF.ROUTEINFO = nil
c.RTF.ANYCAST = nil
c.W.CLONE = nil
c.W.NOTHREAD = nil
c.SCHED.OTHER = nil -- NORMAL in kernel

-- only in Linux headers that conflict
c.IP.NODEFRAG = nil
c.IP.UNICAST_IF = nil

-- not on travis CI box
c.ETH_P["802_EX1"] = nil

-- not included in user headers
c.RUSAGE.BOTH = nil

-- fix these, renamed tables, signals etc
c.SIGTRAP = nil
c.SIGPM = nil
c.SIGILL = nil
c.SIGPOLL = nil
c.SIGCLD = nil
c.SIGFPE = nil
c.SIGSEGV = nil
c.SIGBUS = nil
c.SIGACT = nil

c.SECCOMP_MODE = nil
c.LOCKF = nil
c.SIOC = nil
c.TIOC = nil
c.IFLA_VF_INFO = nil
c.IFLA_VF_PORT = nil
c.TCFLOW = nil
c.TCSA = nil
c.TCFLUSH = nil
c.SECCOMP_RET = nil
c.IN_INIT = nil
c.PR_MCE_KILL_OPT = nil
c.OK = nil
c.EPOLLCREATE = nil
c.STD = nil
c.PORT_PROFILE_RESPONSE = nil
c.AT_FDCWD = nil
c.SYS.fstatat = nil
c.TFD_TIMER = nil
c.MFD = nil

-- this lot are not in uClibc at present
c.ADJ.OFFSET_SS_READ = nil
c.ADJ.NANO = nil
c.ADJ.MICRO = nil
c.ADJ.TAI = nil
c.F.GETPIPE_SZ = nil
c.F.GETOWN_EX = nil
c.F.SETOWN_EX = nil
c.F.SETPIPE_SZ = nil
c.AF.RDS = nil
c.MS.MOVE = nil
c.MS.PRIVATE = nil
c.MS.ACTIVE = nil
c.MS.POSIXACL = nil
c.MS.RELATIME = nil
c.MS.NOUSER = nil
c.MS.SLAVE = nil
c.MS.I_VERSION = nil
c.MS.KERNMOUNT = nil
c.MS.SHARED = nil
c.MS.STRICTATIME = nil
c.MS.UNBINDABLE = nil
c.MS.DIRSYNC = nil
c.MS.SILENT = nil
c.MS.REC = nil
c.RLIMIT.RTTIME = nil
c.UMOUNT.NOFOLLOW = nil
c.STA.MODE = nil
c.STA.CLK = nil
c.STA.NANO = nil
c.CLOCK.MONOTONIC_COARSE = nil
c.CLOCK.REALTIME_COARSE = nil
c.CLOCK.MONOTONIC_RAW = nil
c.SOCK.DCCP = nil

-- missing on my ARM box
c.CAP = nil
c.AF.NFC = nil
c.PR.SET_PTRACER = nil
c.MAP["32BIT"] = nil
c.SYS.sync_file_range = nil
c.AT.EMPTY_PATH = nil

-- now missing on mips, not sure why
c.IFF.MACVLAN_PORT = nil
c.IFF.TX_SKB_SHARING = nil
c.IFF.XMIT_DST_RELEASE = nil
c.IFF.DISABLE_NETPOLL = nil
c.IFF.UNICAST_FLT = nil
c.IFF.OVS_DATAPATH = nil
c.IFF.SLAVE_NEEDARP = nil
c.IFF.ISATAP = nil
c.IFF.MASTER_ARPMON = nil
c.IFF.WAN_HDLC = nil
c.IFF.DONT_BRIDGE = nil
c.IFF.BRIDGE_PORT = nil

-- missing on Travis
c.TCP.THIN_DUPACK = nil
c.TCP.FASTOPEN = nil
c.TCP.REPAIR_OPTIONS = nil
c.TCP.THIN_LINEAR_TIMEOUTS = nil
c.TCP.REPAIR = nil
c.TCP.QUEUE_SEQ = nil
c.TCP.TIMESTAMP = nil
c.TCP.USER_TIMEOUT = nil
c.TCP.REPAIR_QUEUE = nil
c.RTA.NEWDST = nil
c.RTA.PREF = nil
c.RTA.VIA = nil
c.RTA.MFC_STATS = nil

-- these are not in Musl at present TODO send patches to get them in
c.IPPROTO.UDPLITE = nil
c.IPPROTO.DCCP = nil
c.IPPROTO.SCTP = nil
c.CIBAUD = nil
c.F.GETLEASE = nil
c.F.SETLK64 = nil
c.F.NOTIFY = nil
c.F.SETLEASE = nil
c.F.GETLK64 = nil
c.F.SETLKW64 = nil
c.AF.LLC = nil
c.AF.TIPC = nil
c.AF.CAN = nil
c.MSG.TRYHARD = nil
c.MSG.SYN = nil
c.PR_TASK_PERF_EVENTS = nil
c.PR.MCE_KILL = nil
c.PR.MCE_KILL_GET = nil
c.PR.TASK_PERF_EVENTS_ENABLE = nil
c.PR.TASK_PERF_EVENTS_DISABLE = nil
c.PR_ENDIAN.LITTLE = nil
c.PR_ENDIAN.BIG = nil
c.PR_ENDIAN.PPC_LITTLE = nil
c.SIG.IOT = nil
c.SIG.CLD = nil
c.__MAX_BAUD = nil
c.O.FSYNC = nil
c.RLIMIT.OFILE = nil
c.SO.SNDBUFFORCE = nil
c.SO.RCVBUFFORCE = nil
c.POLL.REMOVE = nil
c.POLL.RDHUP = nil
c.PR_MCE_KILL.SET = nil
c.PR_MCE_KILL.CLEAR = nil
c.EXTA = nil
c.EXTB = nil
c.XCASE = nil
c.IUTF8 = nil
c.CMSPAR = nil
c.IN.EXCL_UNLINK = nil
c.MNT.EXPIRE = nil
c.MNT.DETACH = nil
c.SYS.fadvise64_64 = nil

-- travis missing tun tap stuff etc
c.IFF.MULTI_QUEUE = nil
c.IFF.ATTACH_QUEUE = nil
c.IFF.DETACH_QUEUE = nil
c.IOCTL.TUNSETQUEUE = nil
c.TUN.TAP_MQ = nil
c.SO.PEEK_OFF = nil
c.SO.GET_FILTER = nil
c.SO.NOFCS = nil
c.SO.WIFI_STATUS = nil
c.SO.REUSEPORT = nil
c.SO.LOCK_FILTER = nil
c.SO.SELECT_ERR_QUEUE = nil
c.SO.BUSY_POLL = nil
c.SO.MAX_PACING_RATE = nil
c.SO.BPF_EXTENSIONS = nil
c.SO.INCOMING_CPU = nil
c.SO.ATTACH_BPF = nil
c.SO.DETACH_BPF = nil
c.SO.ATTACH_REUSEPORT_CBPF = nil
c.SO.ATTACH_REUSEPORT_EBPF = nil

-- new fcntl
c.F.CANCELLK = nil
c.F.ADD_SEALS = nil
c.F.GET_SEALS = nil
c.F_SEAL = nil

-- Musl changes some of the syscall constants in its 32/64 bit handling
c.SYS.getdents = nil

-- Musl ors O.ACCMODE with O_SEARCH TODO why?
c.O.ACCMODE = nil

if abi.abi64 then c.O.LARGEFILE = nil end

-- not included on ppc?
c.IOCTL.TCSETS2 = nil
c.IOCTL.TCGETS2 = nil
c.IOCTL.TCSETX = nil
c.IOCTL.TCSETXW = nil
c.IOCTL.TCSETSW2 = nil
c.IOCTL.TCSETXF = nil
c.IOCTL.TCGETX = nil
c.IOCTL.TCSETSF2 = nil

-- not on Travis CI
c.PR.GET_TID_ADDRESS = nil
c.NDTPA.QUEUE_LENBYTES = nil
c.NTF.SELF = nil
c.NTF.MASTER = nil
-- no vfio on Travis CI
c.IOCTL.VFIO_GET_API_VERSION = nil
c.IOCTL.VFIO_CHECK_EXTENSION = nil

-- missing on my ppc box/older kernels
c.PR.GET_NO_NEW_PRIVS = nil
c.PR.SET_NO_NEW_PRIVS = nil
c.IP.MULTICAST_ALL = nil
c.EM.TI_C6000 = nil

-- ppc glibc has wrong value, fixed in new constant test
c.CBAUDEX = nil

-- missing on my mips box
c.AUDIT_ARCH.H8300 = nil
-- missing on CI
c.AUDIT_ARCH.AARCH64 = nil

-- defined only in linux/termios.h which we cannot include on mips
c.TIOCM.OUT1 = nil
c.TIOCM.OUT2 = nil
c.TIOCM.LOOP = nil

-- glibc lies about what structure is used on ppc for termios TODO check all these ioctls
if abi.arch == "ppc" then
  ctypes["struct termios"] = nil
  c.IOCTL.TCSETS = nil
  c.IOCTL.TCGETS = nil
  c.IOCTL.TCSETSF = nil
  c.IOCTL.TCSETSW = nil
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

-- constants for new syscalls
c.GRND = nil

if abi.arch == "mips" then
  c.RLIM.INFINITY = nil -- incorrect in all but very recent glibc
end

c.IPV6.FLOWINFO = nil

-- renames
c.LINUX_CAPABILITY_VERSION = c._LINUX_CAPABILITY_VERSION
c.LINUX_CAPABILITY_U32S = c._LINUX_CAPABILITY_U32S

-- include kitchen sink, garbage can etc
print [[
/* this code is generated by ctest-linux.lua */

#define _GNU_SOURCE
#define __USE_GNU
#define _FILE_OFFSET_BITS 64
#define _LARGE_FILES 1
#define __USE_FILE_OFFSET64

#include <stddef.h>
#include <stdint.h>

/* there is inconsistent usage of __LITTLE_ENDIAN so if endian.h included before this it fails! */
#include <linux/aio_abi.h>

#include <stdio.h>
#include <limits.h>
#include <errno.h>
#include <stdlib.h>
#include <sys/types.h>
#include <signal.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/udp.h>
#include <arpa/inet.h>
#include <sys/epoll.h>
#include <sys/utsname.h>
#include <time.h>
#include <sys/resource.h>
#include <sys/sysinfo.h>
#include <sys/time.h>
#include <sys/un.h>
#include <netinet/ip.h>
#include <poll.h>
#include <sys/signalfd.h>
#include <sys/vfs.h>
#include <sys/timex.h>
#include <sys/mman.h>
#include <sched.h>
#include <sys/xattr.h>
#include <termios.h>
#include <unistd.h>
#include <sys/prctl.h>
#include <sys/mount.h>
#include <sys/uio.h>
#include <net/route.h>
#include <sys/inotify.h>
#include <sys/wait.h>
#include <dirent.h>
#include <sys/eventfd.h>
#include <sys/syscall.h>
#include <sys/ioctl.h>
#include <elf.h>
#include <net/ethernet.h>
#include <sys/swap.h>
#include <netinet/tcp.h>
#include <sys/timerfd.h>

#include <linux/capability.h>
#include <linux/reboot.h>
#include <linux/falloc.h>
#include <linux/mman.h>
#include <linux/veth.h>
#include <linux/sockios.h>
#include <linux/if_arp.h>
#include <linux/sched.h>
#include <linux/posix_types.h>
#include <linux/if.h>
#include <linux/if_bridge.h>
#include <linux/rtnetlink.h>
#include <linux/ioctl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <linux/audit.h>
#include <linux/filter.h>
/*#include <linux/seccomp.h>*/
#include <linux/netfilter.h>
#include <linux/netfilter/x_tables.h>
#include <linux/netfilter_ipv4/ip_tables.h>
#include <linux/if_tun.h>
#include <linux/vhost.h>
#include <linux/neighbour.h>
#include <linux/pci.h>
//#include <linux/vfio.h>
#include <linux/virtio_pci.h>

/* not always defined */
#define ENOATTR ENODATA

int ret = 0;

/* not defined anywhere useful */
struct termios2 {
        tcflag_t c_iflag;
        tcflag_t c_oflag;
        tcflag_t c_cflag;
        tcflag_t c_lflag;
        cc_t c_line;
        cc_t c_cc[19];  /* note not using NCCS as redefined! */
        speed_t c_ispeed;
        speed_t c_ospeed;
};

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

-- test all the constants

-- renamed ones
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
}

for k, v in pairs(c) do
  if type(v) == "number" then
    print("sassert(" .. k .. ", " .. v .. ', "' .. k .. '");')
  elseif type(v) == "table" then
    for k2, v2 in pairs(v) do
      local name = nm[k] or k .. "_"
      if type(v2) ~= "function" then
        if type(v2) == "cdata" and ffi.sizeof(v2) == 8 then
         print("sassert_u64(" .. name .. k2 .. ", " .. tostring(v2)  .. ', "' .. name .. k2 .. '");')
        else
         print("sassert(" .. name .. k2 .. ", " .. tostring(v2)  .. ', "' .. name .. k2 .. '");')
        end
      end
    end
  end
end

-- TODO test error codes

print [[
return ret;
}
]]

