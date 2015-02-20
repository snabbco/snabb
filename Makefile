LUASRC = $(wildcard src/lua/*.lua)
LUAOBJ = $(LUASRC:.lua=.o)
CSRC   = $(wildcard src/c/*.c)
COBJ   = $(CSRC:.c=.o)

LUAJIT_O := deps/luajit/src/libluajit.a
SYSCALL  := src/syscall.lua

LUAJIT_CFLAGS := -DLUAJIT_USE_PERFTOOLS -DLUAJIT_USE_GDBJIT -DLUAJIT_NUMMODE=3

all: $(LUAJIT_O) $(SYSCALL)
	cd src && $(MAKE)

install: all
	install -D src/snabb ${PREFIX}/usr/local/bin/snabb

install_db_node:
	install -D src/scripts/sysv/init.d/snabb-nfv-sync-master ${PREFIX}/etc/init.d/snabb-nfv-sync-master
	install -D src/scripts/sysv/default/snabb-nfv-sync-master ${PREFIX}/etc/default/snabb-nfv-sync-master

install_compute_node: install
	install -D src/scripts/sysv/init.d/snabb-nfv-sync-agent ${PREFIX}/etc/init.d/snabb-nfv-sync-agent
	install -D src/scripts/sysv/default/snabb-nfv-sync-agent ${PREFIX}/etc/default/snabb-nfv-sync-agent

$(LUAJIT_O): check_luajit deps/luajit/Makefile
	echo 'Building LuaJIT\n'
	(cd deps/luajit && \
	 $(MAKE) PREFIX=`pwd`/usr/local \
	         CFLAGS="$(LUAJIT_CFLAGS)" && \
	 $(MAKE) DESTDIR=`pwd` install)
	(cd deps/luajit/usr/local/bin; ln -fs luajit-2.1.0-alpha luajit)

check_luajit:
	@if [ ! -f deps/luajit/Makefile ]; then \
	    echo "Can't find deps/luajit/. You might need to: git submodule update --init"; exit 1; \
	fi

$(SYSCALL): check_syscall
	echo 'Copying ljsyscall components'
	mkdir -p src/syscall/linux
	cp -p deps/ljsyscall/syscall.lua   src/
	cp -p deps/ljsyscall/syscall/*.lua src/syscall/
	cp -p  deps/ljsyscall/syscall/linux/*.lua src/syscall/linux/
	cp -pr deps/ljsyscall/syscall/linux/x64   src/syscall/linux/
	cp -pr deps/ljsyscall/syscall/shared      src/syscall/

check_syscall:
	@if [ ! -f deps/ljsyscall/syscall.lua ]; then \
	    echo "Can't find deps/ljsyscall/. You might need to: git submodule update --init"; exit 1; \
	fi

clean:
	(cd deps/luajit && $(MAKE) clean)
	(cd src; $(MAKE) clean; rm -rf syscall.lua syscall)

.SERIAL: all
