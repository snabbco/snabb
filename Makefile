LUASRC = $(wildcard src/lua/*.lua)
LUAOBJ = $(LUASRC:.lua=.o)
CSRC   = $(wildcard src/c/*.c)
COBJ   = $(CSRC:.c=.o)

all:
	(echo 'Building LuaJIT\n'; cd deps/luajit && $(MAKE))
	(echo '\nBuilding LuaFS\n'; cd deps/luafilesystem && $(MAKE) LUA_INC=../luajit/src)
	(cd src && $(MAKE))

clean:
	(cd deps/luajit && $(MAKE) clean)
	(cd deps/luafilesystem && $(MAKE) clean)
	(cd src; $(MAKE) clean)

