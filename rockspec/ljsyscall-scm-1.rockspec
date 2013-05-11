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
      ["syscall.errors"] = "syscall/errors.lua";
      ["syscall.abi"] = "syscall/abi.lua";
      ["syscall.helpers"] = "syscall/helpers.lua";
      ["syscall.syscalls"] = "syscall/syscalls.lua";
      ["syscall.c"] = "syscall/c.lua";
      ["syscall.constants"] = "syscall/constants.lua";
      ["syscall.ffitypes"] = "syscall/ffitypes.lua";
      ["syscall.ffifunctions"] = "syscall/ffifunctions.lua";
      ["syscall.ioctl"] = "syscall/ioctl.lua";
      ["syscall.types"] = "syscall/types.lua";

      ["linux.syscalls"] = "linux/syscalls.lua";
      ["linux.c"] = "linux/c.lua";
      ["linux.constants"] = "linux/constants.lua";
      ["linux.ffitypes"] = "linux/ffitypes.lua";
      ["linux.ffifunctions"] = "linux/ffifunctions.lua";
      ["linux.ioctl"] = "linux/ioctl.lua";
      ["linux.types"] = "linux/types.lua";

      ["linux.features"] = "linux/features.lua";
      ["linux.nl"] = "linux/nl.lua";
      ["linux.netfilter"] = "linux/netfilter.lua";
      ["linux.util"] = "linux/util.lua";
      ["linux.arm.constants"] = "linux/arm/constants.lua";
      ["linux.arm.ffitypes"] = "linux/arm/ffitypes.lua";
      ["linux.arm.ioctl"] = "linux/arm/ioctl.lua";
      ["linux.mips.constants"] = "linux/mips/constants.lua";
      ["linux.ppc.constants"] = "linux/ppc/constants.lua";
      ["linux.ppc.ffitypes"] = "linux/ppc/ffitypes.lua";
      ["linux.ppc.ioctl"] = "linux/ppc/ioctl.lua";
      ["linux.x64.constants"] = "linux/x64/constants.lua";
      ["linux.x64.ffitypes"] = "linux/x64/ffitypes.lua";
      ["linux.x86.constants"] = "linux/x86/constants.lua";
      ["linux.x86.ffitypes"] = "linux/x86/ffitypes.lua";

      ["bsd.syscalls"] = "bsd/syscalls.lua";
      ["bsd.c"] = "bsd/c.lua";
      ["bsd.constants"] = "bsd/constants.lua";
      ["bsd.ffitypes"] = "bsd/ffitypes.lua";
      ["bsd.ffifunctions"] = "bsd/ffifunctions.lua";
      ["bsd.ioctl"] = "bsd/ioctl.lua";
      ["bsd.types"] = "bsd/types.lua";

    };
  };
}
