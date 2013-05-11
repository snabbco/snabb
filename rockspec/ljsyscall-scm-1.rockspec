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

      ["syscall.linux.syscalls"] = "syscall/linux/syscalls.lua";
      ["syscall.linux.c"] = "syscall/linux/c.lua";
      ["syscall.linux.constants"] = "syscall/linux/constants.lua";
      ["syscall.linux.ffitypes"] = "syscall/linux/ffitypes.lua";
      ["syscall.linux.ffifunctions"] = "syscall/linux/ffifunctions.lua";
      ["syscall.linux.ioctl"] = "syscall/linux/ioctl.lua";
      ["syscall.linux.types"] = "syscall/linux/types.lua";

      ["syscall.linux.features"] = "syscall/linux/features.lua";
      ["syscall.linux.nl"] = "syscall/linux/nl.lua";
      ["syscall.linux.netfilter"] = "syscall/linux/netfilter.lua";
      ["syscall.linux.util"] = "syscall/linux/util.lua";
      ["syscall.linux.arm.constants"] = "syscall/linux/arm/constants.lua";
      ["syscall.linux.arm.ffitypes"] = "syscall/linux/arm/ffitypes.lua";
      ["syscall.linux.arm.ioctl"] = "syscall/linux/arm/ioctl.lua";
      ["syscall.linux.mips.constants"] = "syscall/linux/mips/constants.lua";
      ["syscall.linux.ppc.constants"] = "syscall/linux/ppc/constants.lua";
      ["syscall.linux.ppc.ffitypes"] = "syscall/linux/ppc/ffitypes.lua";
      ["syscall.linux.ppc.ioctl"] = "syscall/linux/ppc/ioctl.lua";
      ["syscall.linux.x64.constants"] = "syscall/linux/x64/constants.lua";
      ["syscall.linux.x64.ffitypes"] = "syscall/linux/x64/ffitypes.lua";
      ["syscall.linux.x86.constants"] = "syscall/linux/x86/constants.lua";
      ["syscall.linux.x86.ffitypes"] = "syscall/linux/x86/ffitypes.lua";

      ["syscall.bsd.syscalls"] = "syscall/bsd/syscalls.lua";
      ["syscall.bsd.c"] = "syscall/bsd/c.lua";
      ["syscall.bsd.constants"] = "syscall/bsd/constants.lua";
      ["syscall.bsd.ffitypes"] = "syscall/bsd/ffitypes.lua";
      ["syscall.bsd.ffifunctions"] = "syscall/bsd/ffifunctions.lua";
      ["syscall.bsd.ioctl"] = "syscall/bsd/ioctl.lua";
      ["syscall.bsd.types"] = "syscall/bsd/types.lua";

    };
  };
}
