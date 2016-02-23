package = "ljsyscall"
version = "0.5-1"
source =
{
  url = "https://github.com/justincormack/ljsyscall/archive/v0.5.tar.gz";
  dir = "ljsyscall-0.5";
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
      ["syscall.constants"] = "syscall/constants.lua";
      ["syscall.headers"] = "syscall/headers.lua";
      ["syscall.helpers"] = "syscall/helpers.lua";
      ["syscall.ioctl"] = "syscall/ioctl.lua";
      ["syscall.types"] = "syscall/types.lua";
      ["syscall.nl"] = "syscall/nl.lua";
      ["syscall.arm.constants"] = "syscall/arm/constants.lua";
      ["syscall.arm.ioctl"] = "syscall/arm/ioctl.lua";
      ["syscall.mips.constants"] = "syscall/mips/constants.lua";
      ["syscall.ppc.constants"] = "syscall/ppc/constants.lua";
      ["syscall.ppc.headers"] = "syscall/ppc/headers.lua";
      ["syscall.ppc.ioctl"] = "syscall/ppc/ioctl.lua";
      ["syscall.x64.constants"] = "syscall/x64/constants.lua";
      ["syscall.x64.headers"] = "syscall/x64/headers.lua";
      ["syscall.x86.constants"] = "syscall/x86/constants.lua";
      ["syscall.x86.headers"] = "syscall/x86/headers.lua";
    };
  };
}
