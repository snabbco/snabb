package = "ljsyscall"
version = "0.11-1"
source =
{
  url = "https://github.com/justincormack/ljsyscall/archive/v0.11.tar.gz";
  dir = "ljsyscall-0.11";
}

description =
{
  summary = "LuaJIT Linux syscall FFI";
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
    ["syscall"] = "syscall.lua";
    ["syscall.abi"] = "syscall/abi.lua";
    ["syscall.helpers"] = "syscall/helpers.lua";
    ["syscall.syscalls"] = "syscall/syscalls.lua";
    ["syscall.libc"] = "syscall/libc.lua";
    ["syscall.methods"] = "syscall/methods.lua";
    ["syscall.ffitypes"] = "syscall/ffitypes.lua";
    ["syscall.util"] = "syscall/util.lua";
    ["syscall.compat"] = "syscall/compat.lua";
    ["syscall.bit"] = "syscall/bit.lua";
    ["syscall.types"] = "syscall/types.lua";
    ["syscall.lfs"] = "syscall/lfs.lua";

    ["syscall.shared.types"] = "syscall/shared/types.lua";
  };
  platforms =
  {
    linux =
    {
      modules = {
        ["syscall.linux.syscalls"] = "syscall/linux/syscalls.lua";
        ["syscall.linux.c"] = "syscall/linux/c.lua";
        ["syscall.linux.constants"] = "syscall/linux/constants.lua";
        ["syscall.linux.ffi"] = "syscall/linux/ffi.lua";
        ["syscall.linux.ioctl"] = "syscall/linux/ioctl.lua";
        ["syscall.linux.types"] = "syscall/linux/types.lua";
        ["syscall.linux.fcntl"] = "syscall/linux/fcntl.lua";
        ["syscall.linux.errors"] = "syscall/linux/errors.lua";
        ["syscall.linux.util"] = "syscall/linux/util.lua";
        ["syscall.linux.nr"] = "syscall/linux/nr.lua";

        ["syscall.linux.nl"] = "syscall/linux/nl.lua";
        ["syscall.linux.netfilter"] = "syscall/linux/netfilter.lua";
        ["syscall.linux.sockopt"] = "syscall/linux/sockopt.lua";
        ["syscall.linux.cgroup"] = "syscall/linux/cgroup.lua";

        ["syscall.linux.arm.constants"] = "syscall/linux/arm/constants.lua";
        ["syscall.linux.arm.ffi"] = "syscall/linux/arm/ffi.lua";
        ["syscall.linux.arm.ioctl"] = "syscall/linux/arm/ioctl.lua";
        ["syscall.linux.arm.nr"] = "syscall/linux/arm/nr.lua";
        ["syscall.linux.arm64.constants"] = "syscall/linux/arm64/constants.lua";
        ["syscall.linux.arm64.ffi"] = "syscall/linux/arm64/ffi.lua";
        ["syscall.linux.arm64.ioctl"] = "syscall/linux/arm64/ioctl.lua";
        ["syscall.linux.arm64.nr"] = "syscall/linux/arm64/nr.lua";
        ["syscall.linux.mips.constants"] = "syscall/linux/mips/constants.lua";
        ["syscall.linux.mips.ffi"] = "syscall/linux/mips/ffi.lua";
        ["syscall.linux.mips.ioctl"] = "syscall/linux/mips/ioctl.lua";
        ["syscall.linux.mips.nr"] = "syscall/linux/mips/nr.lua";
        ["syscall.linux.ppc.constants"] = "syscall/linux/ppc/constants.lua";
        ["syscall.linux.ppc.ffi"] = "syscall/linux/ppc/ffi.lua";
        ["syscall.linux.ppc.ioctl"] = "syscall/linux/ppc/ioctl.lua";
        ["syscall.linux.ppc.nr"] = "syscall/linux/ppc/nr.lua";
        ["syscall.linux.ppc64le.constants"] = "syscall/linux/ppc64le/constants.lua";
        ["syscall.linux.ppc64le.ffi"] = "syscall/linux/ppc64le/ffi.lua";
        ["syscall.linux.ppc64le.ioctl"] = "syscall/linux/ppc64le/ioctl.lua";
        ["syscall.linux.ppc64le.nr"] = "syscall/linux/ppc64le/nr.lua";
        ["syscall.linux.x64.constants"] = "syscall/linux/x64/constants.lua";
        ["syscall.linux.x64.ffi"] = "syscall/linux/x64/ffi.lua";
        ["syscall.linux.x64.ioctl"] = "syscall/linux/x64/ioctl.lua";
        ["syscall.linux.x64.nr"] = "syscall/linux/x64/nr.lua";
        ["syscall.linux.x86.constants"] = "syscall/linux/x86/constants.lua";
        ["syscall.linux.x86.ffi"] = "syscall/linux/x86/ffi.lua";
        ["syscall.linux.x86.ioctl"] = "syscall/linux/x86/ioctl.lua";
        ["syscall.linux.x86.nr"] = "syscall/linux/x86/nr.lua";
      }
    };
    macosx =
    {
      modules =
      {
        ["syscall.osx.syscalls"] = "syscall/osx/syscalls.lua";
        ["syscall.osx.c"] = "syscall/osx/c.lua";
        ["syscall.osx.constants"] = "syscall/osx/constants.lua";
        ["syscall.osx.ffi"] = "syscall/osx/ffi.lua";
        ["syscall.osx.ioctl"] = "syscall/osx/ioctl.lua";
        ["syscall.osx.types"] = "syscall/osx/types.lua";
        ["syscall.osx.fcntl"] = "syscall/osx/fcntl.lua";
        ["syscall.osx.errors"] = "syscall/osx/errors.lua";
        ["syscall.osx.util"] = "syscall/osx/util.lua";
        ["syscall.osx.sysctl"] = "syscall/osx/sysctl.lua";
      }
    };
    freebsd =
    {
      modules =
      {
        ["syscall.freebsd.syscalls"] = "syscall/freebsd/syscalls.lua";
        ["syscall.freebsd.c"] = "syscall/freebsd/c.lua";
        ["syscall.freebsd.constants"] = "syscall/freebsd/constants.lua";
        ["syscall.freebsd.ffi"] = "syscall/freebsd/ffi.lua";
        ["syscall.freebsd.ioctl"] = "syscall/freebsd/ioctl.lua";
        ["syscall.freebsd.types"] = "syscall/freebsd/types.lua";
        ["syscall.freebsd.fcntl"] = "syscall/freebsd/fcntl.lua";
        ["syscall.freebsd.errors"] = "syscall/freebsd/errors.lua";
        ["syscall.freebsd.util"] = "syscall/freebsd/util.lua";
        ["syscall.freebsd.version"] = "syscall/freebsd/version.lua";
        ["syscall.freebsd.sysctl"] = "syscall/freebsd/sysctl.lua";
      }
    };
    netbsd =
    {
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
        ["syscall.netbsd.init"] = "syscall/netbsd/init.lua";
        ["syscall.netbsd.version"] = "syscall/netbsd/version.lua";
        ["syscall.netbsd.sysctl"] = "syscall/netbsd/sysctl.lua";
      }
    };
    openbsd =
    {
      modules =
      {
        ["syscall.openbsd.syscalls"] = "syscall/openbsd/syscalls.lua";
        ["syscall.openbsd.c"] = "syscall/openbsd/c.lua";
        ["syscall.openbsd.constants"] = "syscall/openbsd/constants.lua";
        ["syscall.openbsd.ffi"] = "syscall/openbsd/ffi.lua";
        ["syscall.openbsd.ioctl"] = "syscall/openbsd/ioctl.lua";
        ["syscall.openbsd.types"] = "syscall/openbsd/types.lua";
        ["syscall.openbsd.fcntl"] = "syscall/openbsd/fcntl.lua";
        ["syscall.openbsd.errors"] = "syscall/openbsd/errors.lua";
        ["syscall.openbsd.util"] = "syscall/openbsd/util.lua";
        ["syscall.openbsd.version"] = "syscall/openbsd/version.lua";
        ["syscall.openbsd.sysctl"] = "syscall/openbsd/sysctl.lua";
      }
    };
    bsd =
    {
      modules =
      {
        ["syscall.bsd.syscalls"] = "syscall/bsd/syscalls.lua";
        ["syscall.bsd.ffi"] = "syscall/bsd/ffi.lua";
        ["syscall.bsd.types"] = "syscall/bsd/types.lua";
      }
    };
  }
}
