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
      ["syscall.syscalls"] = "syscall/syscalls.lua";
      ["syscall.abi"] = "syscall/abi.lua";
      ["syscall.c"] = "syscall/c.lua";
      ["syscall.constants"] = "syscall/constants.lua";
      ["syscall.ffitypes"] = "syscall/ffitypes.lua";
      ["syscall.ffifunctions"] = "syscall/ffifunctions.lua";
      ["syscall.helpers"] = "syscall/helpers.lua";
      ["syscall.ioctl"] = "syscall/ioctl.lua";
      ["syscall.types"] = "syscall/types.lua";
      ["syscall.errors"] = "syscall/errors.lua";
      ["syscall.nl"] = "syscall/nl.lua";
      ["syscall.util"] = "syscall/util.lua";
      ["syscall.features"] = "syscall/features.lua";
      ["syscall.netfilter"] = "syscall/netfilter.lua";
      ["syscall.arm.constants"] = "syscall/arm/constants.lua";
      ["syscall.arm.ffitypes"] = "syscall/arm/ffitypes.lua";
      ["syscall.arm.ioctl"] = "syscall/arm/ioctl.lua";
      ["syscall.mips.constants"] = "syscall/mips/constants.lua";
      ["syscall.ppc.constants"] = "syscall/ppc/constants.lua";
      ["syscall.ppc.ffitypes"] = "syscall/ppc/ffitypes.lua";
      ["syscall.ppc.ioctl"] = "syscall/ppc/ioctl.lua";
      ["syscall.x64.constants"] = "syscall/x64/constants.lua";
      ["syscall.x64.ffitypes"] = "syscall/x64/ffitypes.lua";
      ["syscall.x86.constants"] = "syscall/x86/constants.lua";
      ["syscall.x86.ffitypes"] = "syscall/x86/ffitypes.lua";
    };
  };
}
