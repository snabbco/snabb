/* Copyright 2012 Snabb GmbH. See the file COPYING for license details. */

#include <stdio.h>

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

/* the Lua interpreter */
lua_State* L;

int main(void)
{
  L = luaL_newstate();
  luaL_openlibs(L);
  (void)luaL_dostring(L, "require switch");
  lua_close(L);

  return 0;
}
