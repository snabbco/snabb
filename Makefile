LUASRC = $(wildcard src/lua/*.lua)
LUAOBJ = $(LUASRC:.lua=.o)
CSRC   = $(wildcard src/c/*.c)
COBJ   = $(CSRC:.c=.o)

LUAJIT_O := deps/luajit/src/libluajit.a
LFS_O    := deps/luafilesystem/src/lfs.o

all: $(LUAJIT_O) $(LFS_O)
	cd src && $(MAKE)

$(LUAJIT_O): deps/luajit/Makefile
	(echo 'Building LuaJIT\n'; cd deps/luajit && $(MAKE) PREFIX=`pwd`/usr/local && $(MAKE) DESTDIR=`pwd` install)

$(LFS_O): deps/luafilesystem/Makefile
	(echo '\nBuilding LuaFS\n'; cd deps/luafilesystem && $(MAKE) LUA_INC=../luajit/src)

clean:
	(cd deps/luajit && $(MAKE) clean)
	(cd deps/luafilesystem && $(MAKE) clean)
	(cd src; $(MAKE) clean)

.SERIAL: all
