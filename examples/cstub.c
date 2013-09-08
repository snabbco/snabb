/* simple example to show a C file linked with ljsyscall */

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include <stdlib.h>
#include <stdio.h>

void lerror(lua_State *L, char *msg) {
  fprintf(stderr, "\nFATAL ERROR:\n  %s: %s\n\n", msg, lua_tostring(L, -1));
  lua_close(L);
  exit(1);
}

int main(void) {
  lua_State *L;

  L = luaL_newstate();
  luaL_openlibs(L);

  if (luaL_loadstring(L, "require \"test.test\""))
	lerror(L, "luaL_loadstring() failed");
  if (lua_pcall(L, 0, 0, 0))
	lerror(L, "lua_pcall() failed");

  lua_close(L);

  return 0;
}
