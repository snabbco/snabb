package = "ljsyscall-rump"
version = "0.9-1"
source =
{
  url = "https://github.com/justincormack/ljsyscall/archive/v0.9.tar.gz";
  dir = "ljsyscall-0.9";
}

description =
{
  summary = "Rump kernel support for LuaJIT syscall FFI";
  homepage = "http://www.myriabit.com/ljsyscall/";
  license = "MIT";
}
dependencies =
{
  "lua == 5.1"; -- In fact this should be "luajit >= 2.0.0"
  "ljsyscall == 0.9";
  "ljsyscall-netbsd == 0.9";
}
build =
{
  type = "builtin";
  modules =
  {
    ["syscall.rump.init"] = "syscall/rump/init.lua";
    ["syscall.rump.c"] = "syscall/rump/c.lua";
    ["syscall.rump.ffirump"] = "syscall/rump/ffirump.lua";
  };
}
