LUASRC = $(wildcard src/lua/*.lua)
LUAOBJ = $(LUASRC:.lua=.o)
CSRC   = $(wildcard src/c/*.c)
COBJ   = $(CSRC:.c=.o)

LUAJIT_O := deps/luajit/src/libluajit.a

all: $(LUAJIT_O)
	cd src && $(MAKE)

$(LUAJIT_O): deps/luajit/Makefile
	(echo 'Building LuaJIT\n'; cd deps/luajit && $(MAKE) PREFIX=`pwd`/usr/local && $(MAKE) DESTDIR=`pwd` install)

clean:
	(cd deps/luajit && $(MAKE) clean)
	(cd src; $(MAKE) clean)

.SERIAL: all
