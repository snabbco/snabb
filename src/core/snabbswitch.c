#include <stdio.h>

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

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

