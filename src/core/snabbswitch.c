/* Use of this source code is governed by the Apache 2.0 license; see COPYING. */

#include <stdio.h>

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

#include <stdint.h>

#if UINTPTR_MAX != UINT64_MAX
#error "64-bit word size required. See doc/porting.md."
#endif

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

