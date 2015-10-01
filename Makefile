LUASRC = $(wildcard src/lua/*.lua)
LUAOBJ = $(LUASRC:.lua=.o)
CSRC   = $(wildcard src/c/*.c)
COBJ   = $(CSRC:.c=.o)

LUAJIT_CFLAGS := -include $(CURDIR)/gcc-preinclude.h

all: $(LUAJIT) $(SYSCALL) $(PFLUA)
#       LuaJIT
	@(cd lib/luajit && \
	 $(MAKE) PREFIX=`pwd`/usr/local \
	         CFLAGS="$(LUAJIT_CFLAGS)" && \
	 $(MAKE) DESTDIR=`pwd` install)
	(cd lib/luajit/usr/local/bin; ln -fs luajit-2.1.0-beta1 luajit)
#       ljsyscall
	@mkdir -p src/syscall/linux
	@cp -p lib/ljsyscall/syscall.lua   src/
	@cp -p lib/ljsyscall/syscall/*.lua src/syscall/
	@cp -p  lib/ljsyscall/syscall/linux/*.lua src/syscall/linux/
	@cp -pr lib/ljsyscall/syscall/linux/x64   src/syscall/linux/
	@cp -pr lib/ljsyscall/syscall/shared      src/syscall/
	cd src && $(MAKE)

install: all
	install -D src/snabb ${PREFIX}/usr/local/bin/snabb

clean:
	(cd lib/luajit && $(MAKE) clean)
	(cd src; $(MAKE) clean; rm -rf syscall.lua syscall)

PACKAGE:=snabbswitch
DIST_BINARY:=snabb
BUILDDIR:=$(shell pwd)

dist: DISTDIR:=$(BUILDDIR)/$(PACKAGE)-$(shell git describe --tags)
dist: all
	mkdir "$(DISTDIR)"
	git clone "$(BUILDDIR)" "$(DISTDIR)/$(PACKAGE)"
	git clone "$(BUILDDIR)/deps/luajit" "$(DISTDIR)/$(PACKAGE)/deps/luajit"
	git clone "$(BUILDDIR)/deps/ljsyscall" "$(DISTDIR)/$(PACKAGE)/deps/ljsyscall"
	git clone "$(BUILDDIR)/deps/pflua" "$(DISTDIR)/$(PACKAGE)/deps/pflua"
	rm -rf "$(DISTDIR)/$(PACKAGE)/.git"
	rm -rf "$(DISTDIR)/$(PACKAGE)/deps/luajit/.git"
	rm -rf "$(DISTDIR)/$(PACKAGE)/deps/ljsyscall/.git"
	rm -rf "$(DISTDIR)/$(PACKAGE)/deps/pflua/.git"
	cp "$(BUILDDIR)/src/$(DIST_BINARY)" "$(DISTDIR)/$(DIST_BINARY)"
	cd "$(DISTDIR)/.." && tar cJvf "`basename '$(DISTDIR)'`.tar.xz" "`basename '$(DISTDIR)'`"
	rm -rf "$(DISTDIR)"

.SERIAL: all
