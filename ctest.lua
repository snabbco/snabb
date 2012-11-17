-- generate C test file to check type sizes etc
-- luajit ctest.lua > ctest.c && cc ctest.c -o ctest && ./ctest

local S = require "syscall"
local ffi = require "ffi"

local s, t, c, ctypes = S.s, S.t, S.c, S.ctypes

-- TODO fix these, various naming issues
ctypes["struct linux_dirent64"] = nil
ctypes["struct statfs64"] = nil
ctypes["struct flock64"] = nil
ctypes["struct stat64"] = nil
ctypes["struct fdb_entry"] = nil
ctypes["struct seccomp_data"] = nil
ctypes["sighandler_t"] = nil
ctypes["struct rlimit64"] = nil
ctypes["struct mq_attr"] = nil

-- fake constants
c.MS.RO = nil
c.MS.RW = nil
c.IFF.ALL = nil
c.IFF.NONE = nil

-- TODO find the headers/flags for these if exist, or remove
c.SA.RESTORER = nil
c.AF.DECNET = nil
c.SIG.HOLD = nil
c.NOTHREAD = nil
c.RTF.PREFIX_RT = nil
c.RTF.EXPIRES = nil
c.RTF.ROUTEINFO = nil
c.RTF.ANYCAST = nil

-- renamed constants
c.O.NONBLOCK = c.OPIPE.NONBLOCK
c.O.CLOEXEC = c.OPIPE.CLOEXEC
c.OPIPE = nil

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
for k, v in pairs(ctypes) do
  print("assert(sizeof(" .. k .. ") == " .. ffi.sizeof(v) .. ");")
end

-- test all the constants

local nm = {
  E = "E",
  

}

for k, v in pairs(c) do
  if type(v) == "number" then
    print("assert(" .. k .. " == " .. v .. ");")
  elseif type(v) == "table" then
    for k2, v2 in pairs(v) do
      local name = nm[k] or k .. "_"
      print("assert(" .. name .. k2 .. " == " .. tostring(v2) .. ");")
    end
  end
end

-- TODO test error codes

print [[
}
]]

