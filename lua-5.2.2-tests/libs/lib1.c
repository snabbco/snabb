/*
** compile with
** Linux: gcc -Wall -O2 -I.. -ansi -shared -o lib1.so lib1.c
** Mac OS X: export MACOSX_DEPLOYMENT_TARGET=10.3
**     gcc -bundle -undefined dynamic_lookup -Wall -O2 -o lib1.so lib1.c
*/


#include "lua.h"
#include "lauxlib.h"

static int id (lua_State *L) {
  return lua_gettop(L);
}


static const struct luaL_Reg funcs[] = {
  {"id", id},
  {NULL, NULL}
};


/* function used by lib11.c */
int lib1_export (lua_State *L) {
  lua_pushstring(L, "exported");
  return 1;
}


int onefunction (lua_State *L) {
  lua_settop(L, 2);
  lua_pushvalue(L, 1);
  return 2;
}


int anotherfunc (lua_State *L) {
  lua_pushfstring(L, "%f%f\n", lua_tonumber(L, 1), lua_tonumber(L, 2));
  return 1;
} 


int luaopen_lib1_sub (lua_State *L) {
  lua_setglobal(L, "y");
  lua_setglobal(L, "x");
  luaL_newlib(L, funcs);
  return 1;
}

