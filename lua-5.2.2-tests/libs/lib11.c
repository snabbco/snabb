/*
** compile with
** Linux: gcc -Wall -O2 -I.. -ansi -shared -o lib1.so lib1.c
** Mac OS X: export MACOSX_DEPLOYMENT_TARGET=10.3
**     gcc -bundle -undefined dynamic_lookup -Wall -O2 -o lib1.so lib1.c
*/


#include "lua.h"

/* function from lib1.c */
int lib1_export (lua_State *L);

int luaopen_lib11 (lua_State *L) {
  return lib1_export(L);
}


