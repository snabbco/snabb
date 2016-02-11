#include <stdio.h>

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

#if sizeof(uint64_t) != sizeof(uintptr_t)
#error "Snabb only supports 64-bit platforms. See https://github.com/SnabbCo/snabbswitch/blob/master/src/doc/porting.md"
#end

int argc;
char** argv;

int main(int snabb_argc, char **snabb_argv)
{
  /* Store for use by LuaJIT code via FFI. */
  argc = snabb_argc;
  argv = snabb_argv;
  lua_State* L = luaL_newstate();
  luaL_openlibs(L);
  return luaL_dostring(L, "require \"core.startup\"");
}

