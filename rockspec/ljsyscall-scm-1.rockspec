package = "ljsyscall"
version = "scm-1"
source =
{
  url = "git://github.com/justincormack/ljsyscall.git";
  branch = "master";
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
  type = "none";
  install =
  {
    lua =
    {
      ["syscall"] = "syscall.lua";
      ["syscall.abi"] = "syscall/abi.lua";
      ["syscall.helpers"] = "syscall/helpers.lua";
      ["syscall.syscalls"] = "syscall/syscalls.lua";
      ["syscall.ffifunctions"] = "syscall/ffifunctions.lua";
      ["syscall.libc"] = "syscall/libc.lua";
      ["syscall.methods"] = "syscall/methods.lua";
      ["syscall.ffitypes"] = "syscall/ffitypes.lua";
      ["syscall.util"] = "syscall/util.lua";
      ["syscall.compat"] = "syscall/compat.lua";
      ["syscall.bit"] = "syscall/bit.lua";
      ["syscall.types"] = "syscall/types.lua";

      ["syscall.shared.types"] = "syscall/shared/types.lua";

      ["syscall.linux.syscalls"] = "syscall/linux/syscalls.lua";
      ["syscall.linux.c"] = "syscall/linux/c.lua";
      ["syscall.linux.constants"] = "syscall/linux/constants.lua";
      ["syscall.linux.ffitypes"] = "syscall/linux/ffitypes.lua";
      ["syscall.linux.ffifunctions"] = "syscall/linux/ffifunctions.lua";
      ["syscall.linux.ioctl"] = "syscall/linux/ioctl.lua";
      ["syscall.linux.types"] = "syscall/linux/types.lua";
      ["syscall.linux.fcntl"] = "syscall/linux/fcntl.lua";
      ["syscall.linux.errors"] = "syscall/linux/errors.lua";
      ["syscall.linux.compat"] = "syscall/linux/compat.lua";
      ["syscall.linux.util"] = "syscall/linux/util.lua";
      ["syscall.linux.nr"] = "syscall/linux/nr.lua";

      ["syscall.linux.nl"] = "syscall/linux/nl.lua";
      ["syscall.linux.netfilter"] = "syscall/linux/netfilter.lua";
      ["syscall.linux.sockopt"] = "syscall/linux/sockopt.lua";
      ["syscall.linux.cgroup"] = "syscall/linux/cgroup.lua";

      ["syscall.linux.arm.constants"] = "syscall/linux/arm/constants.lua";
      ["syscall.linux.arm.ffitypes"] = "syscall/linux/arm/ffitypes.lua";
      ["syscall.linux.arm.ioctl"] = "syscall/linux/arm/ioctl.lua";
      ["syscall.linux.arm.nr"] = "syscall/linux/arm/nr.lua";
      ["syscall.linux.mips.constants"] = "syscall/linux/mips/constants.lua";
      ["syscall.linux.mips.ffitypes"] = "syscall/linux/mips/ffitypes.lua";
      ["syscall.linux.mips.ioctl"] = "syscall/linux/mips/ioctl.lua";
      ["syscall.linux.mips.nr"] = "syscall/linux/mips/nr.lua";
      ["syscall.linux.ppc.constants"] = "syscall/linux/ppc/constants.lua";
      ["syscall.linux.ppc.ffitypes"] = "syscall/linux/ppc/ffitypes.lua";
      ["syscall.linux.ppc.ioctl"] = "syscall/linux/ppc/ioctl.lua";
      ["syscall.linux.ppc.nr"] = "syscall/linux/ppc/nr.lua";
      ["syscall.linux.x64.constants"] = "syscall/linux/x64/constants.lua";
      ["syscall.linux.x64.ffitypes"] = "syscall/linux/x64/ffitypes.lua";
      ["syscall.linux.x64.ioctl"] = "syscall/linux/x64/ioctl.lua";
      ["syscall.linux.x64.nr"] = "syscall/linux/x64/nr.lua";
      ["syscall.linux.x86.constants"] = "syscall/linux/x86/constants.lua";
      ["syscall.linux.x86.ffitypes"] = "syscall/linux/x86/ffitypes.lua";
      ["syscall.linux.x86.ioctl"] = "syscall/linux/x86/ioctl.lua";
      ["syscall.linux.x86.nr"] = "syscall/linux/x86/nr.lua";

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

      ["syscall.osx.syscalls"] = "syscall/osx/syscalls.lua";
      ["syscall.osx.c"] = "syscall/osx/c.lua";
      ["syscall.osx.constants"] = "syscall/osx/constants.lua";
      ["syscall.osx.ffitypes"] = "syscall/osx/ffitypes.lua";
      ["syscall.osx.ffifunctions"] = "syscall/osx/ffifunctions.lua";
      ["syscall.osx.ioctl"] = "syscall/osx/ioctl.lua";
      ["syscall.osx.types"] = "syscall/osx/types.lua";
      ["syscall.osx.fcntl"] = "syscall/osx/fcntl.lua";
      ["syscall.osx.errors"] = "syscall/osx/errors.lua";
      ["syscall.osx.util"] = "syscall/osx/util.lua";

      ["syscall.freebsd.syscalls"] = "syscall/freebsd/syscalls.lua";
      ["syscall.freebsd.c"] = "syscall/freebsd/c.lua";
      ["syscall.freebsd.constants"] = "syscall/freebsd/constants.lua";
      ["syscall.freebsd.ffitypes"] = "syscall/freebsd/ffitypes.lua";
      ["syscall.freebsd.ffifunctions"] = "syscall/freebsd/ffifunctions.lua";
      ["syscall.freebsd.ioctl"] = "syscall/freebsd/ioctl.lua";
      ["syscall.freebsd.types"] = "syscall/freebsd/types.lua";
      ["syscall.freebsd.fcntl"] = "syscall/freebsd/fcntl.lua";
      ["syscall.freebsd.errors"] = "syscall/freebsd/errors.lua";
      ["syscall.freebsd.util"] = "syscall/freebsd/util.lua";

      ["syscall.bsd.syscalls"] = "syscall/bsd/syscalls.lua";
      ["syscall.bsd.ffifunctions"] = "syscall/bsd/ffifunctions.lua";
      ["syscall.bsd.types"] = "syscall/bsd/types.lua";

      ["syscall.rump.init"] = "syscall/rump/init.lua";
      ["syscall.rump.c"] = "syscall/rump/c.lua";
      ["syscall.rump.ffirump"] = "syscall/rump/ffirump.lua";
    };
  };
}
