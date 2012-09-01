-- generate C test file to check type sizes etc

local S = require "syscall"
local ffi = require "ffi"

local s, t = S.s, S.t

-- TODO fix these, various naming issues
S.ctypes["struct linux_dirent64"] = nil
S.ctypes["struct statfs64"] = nil
S.ctypes["struct flock64"] = nil
S.ctypes["struct fdb_entry"] = nil

-- include kitchen sink, garbage can etc
print [[
#include "assert.h"

#define __USE_GNU

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
#include <linux/seccomp.h>
#include <linux/posix_types.h>
#include <linux/if.h>
#include <linux/if_bridge.h>

int main(int argc, char **argv) {
]]

-- iterate over S.ctypes

for k, v in pairs(S.ctypes) do
  print("assert(sizeof(" .. k .. ") == " .. ffi.sizeof(v) .. ");")
end;

print [[
}
]]

