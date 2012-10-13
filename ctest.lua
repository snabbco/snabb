-- generate C test file to check type sizes etc

local S = require "syscall"
local ffi = require "ffi"

local s, t = S.s, S.t

-- TODO fix these, various naming issues
S.ctypes["struct linux_dirent64"] = nil
S.ctypes["struct statfs64"] = nil
S.ctypes["struct flock64"] = nil
S.ctypes["struct stat64"] = nil
S.ctypes["struct fdb_entry"] = nil
S.ctypes["struct seccomp_data"] = nil
S.ctypes["sighandler_t"] = nil
S.ctypes["struct rlimit64"] = nil
S.ctypes["struct mq_attr"] = nil

-- fixes for constants
S.__WALL = S.WALL; S.WALL = nil
S.__WCLONE = S.WCLONE; S.WCLONE = nil

-- remove seccomp for now as no support on the ARM box
for k, _ in pairs(S) do
  if k:sub(1, 8) == 'SECCOMP_' then S[k] = nil end
end

-- fake constants
S.MS_RO = nil
S.MS_RW = nil
S.IFF_ALL = nil
S.IFF_NONE = nil

-- TODO find the headers/flags for these if exist, or remove
S.SA_RESTORER = nil
S.AF_DECNET = nil
S.SIG_HOLD = nil
S.NOTHREAD = nil
S.RTF_PREFIX_RT = nil
S.RTF_EXPIRES = nil
S.RTF_ROUTEINFO = nil
S.RTF_ANYCAST = nil

-- include kitchen sink, garbage can etc
print [[
#include "assert.h"

#define _GNU_SOURCE
#define __USE_GNU
#define _FILE_OFFSET_BITS 64
#define _LARGE_FILES 1
#define __USE_FILE_OFFSET64

#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/epoll.h>
#include <signal.h>
#include <sys/utsname.h>
#include <time.h>
#include <linux/aio_abi.h>
#include <sys/resource.h>
#include <sys/sysinfo.h>
#include <sys/time.h>
#include <sys/un.h>
#include <netinet/ip.h>
#include <poll.h>
#include <sys/signalfd.h>
#include <linux/rtnetlink.h>
#include <sys/vfs.h>
#include <sys/timex.h>
#include <linux/posix_types.h>
#include <linux/if.h>
#include <linux/if_bridge.h>
#include <sys/mman.h>
#include <sched.h>
#include <sys/xattr.h>
#include <linux/if_arp.h>
#include <sys/capability.h>
#include <linux/sched.h>
#include <termios.h>
#include <unistd.h>
#include <sys/prctl.h>
#include <sys/mount.h>
#include <sys/uio.h>
#include <net/route.h>
#include <sys/inotify.h>
#include <sys/wait.h>
#include <linux/mman.h>
#include <linux/veth.h>
#include <linux/sockios.h>
#include <dirent.h>
#include <linux/reboot.h>
#include <sys/timerfd.h>
#include <linux/falloc.h>
#include <sys/eventfd.h>

int main(int argc, char **argv) {
]]

-- iterate over S.ctypes
for k, v in pairs(S.ctypes) do
  print("assert(sizeof(" .. k .. ") == " .. ffi.sizeof(v) .. ");")
end

-- test all the constants

for k, v in pairs(S) do
  if type(S[k]) == "number" then
    print("assert(" .. k .. " == " .. v .. ");")
  end
end

-- TODO test error codes

print [[
}
]]

