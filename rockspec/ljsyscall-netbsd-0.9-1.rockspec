package = "ljsyscall-netbsd"
version = "0.9-1"
source =
{
  url = "https://github.com/justincormack/ljsyscall/archive/v0.9.tar.gz";
  dir = "ljsyscall-0.9";
}

description =
{
  summary = "NetBSD modules for LuaJIT syscall FFI";
  detailed = [[
     NetBSD support for ljsyscall, also used by rump kernel support.
  ]];
  homepage = "http://www.myriabit.com/ljsyscall/";
  license = "MIT";
}
dependencies =
{
  "lua == 5.1"; -- In fact this should be "luajit >= 2.0.0"
}
build =
{
  type = "builtin";
  modules =
  {
    ["syscall.netbsd.syscalls"] = "syscall/netbsd/syscalls.lua";
    ["syscall.netbsd.c"] = "syscall/netbsd/c.lua";
    ["syscall.netbsd.constants"] = "syscall/netbsd/constants.lua";
    ["syscall.netbsd.ffitypes"] = "syscall/netbsd/ffitypes.lua";
    ["syscall.netbsd.ffifunctions"] = "syscall/netbsd/ffifunctions.lua";
    ["syscall.netbsd.ioctl"] = "syscall/netbsd/ioctl.lua";
    ["syscall.netbsd.types"] = "syscall/netbsd/types.lua";
    ["syscall.netbsd.fcntl"] = "syscall/netbsd/fcntl.lua";
    ["syscall.netbsd.errors"] = "syscall/netbsd/errors.lua";
    ["syscall.netbsd.util"] = "syscall/netbsd/util.lua";
    ["syscall.netbsd.nr"] = "syscall/netbsd/nr.lua";
  }
}
