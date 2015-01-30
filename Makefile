LUASRC = $(wildcard src/lua/*.lua)
LUAOBJ = $(LUASRC:.lua=.o)
CSRC   = $(wildcard src/c/*.c)
COBJ   = $(CSRC:.c=.o)

LUAJIT_O := deps/luajit/src/libluajit.a

LUAJIT_CFLAGS := -DLUAJIT_USE_PERFTOOLS -DLUAJIT_USE_GDBJIT -DLUAJIT_NUMMODE=3 -include $(CURDIR)/gcc-preinclude.h

all: $(LUAJIT_O)
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

clean:
	(cd deps/luajit && $(MAKE) clean)
	(cd src; $(MAKE) clean)

.SERIAL: all
