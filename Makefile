PWD=$(shell pwd)

#luajit related stuff
LUAJIT_PREFIX?=$(PWD)/deps/.install
LUAJIT_INSTALL_PATH=$(LUAJIT_PREFIX)/usr/local
LUAJIT_LIB=$(LUAJIT_INSTALL_PATH)/lib

export LUAJIT=$(LUAJIT_INSTALL_PATH)/bin/luajit-2.1.0-alpha
export DYNASM_LUA=$(LUAJIT_INSTALL_PATH)/share/luajit-2.1.0-alpha/dynasm/dynasm.lua
ifneq ("","$(LUAJIT_DYNAMIC_LINK)")
export CFLAGS_LUAJIT= -L$(LUAJIT_LIB) -lluajit-5.1
else
export CFLAGS_LUAJIT= $(LUAJIT_LIB)/libluajit.a
endif
export CFLAGS_DEPS = -I $(LUAJIT_INSTALL_PATH)/include/luajit-2.1 -I $(PWD)/deps/include

LUAJIT_CFLAGS := -DLUAJIT_USE_PERFTOOLS -DLUAJIT_USE_GDBJIT -DLUAJIT_NUMMODE=3

all: $(LUAJIT)
	cd src && $(MAKE)

$(LUAJIT): check_luajit
ifneq ("","$(wildcard deps/luajit/Makefile)")
	echo 'Building LuaJIT\n'
	(cd deps/luajit && \
	 $(MAKE) PREFIX=$(LUAJIT_PREFIX)/usr/local \
	         CFLAGS="$(LUAJIT_CFLAGS)" && \
	 $(MAKE) DESTDIR=$(LUAJIT_PREFIX) install)
	# install the static library
	install deps/luajit/src/libluajit.a \
			$(LUAJIT_LIB)/libluajit.a
	# dynasm is not installed so copy the necessary files
	install -d $(LUAJIT_INSTALL_PATH)/share/luajit-2.1.0-alpha/dynasm \
			   $(LUAJIT_INSTALL_PATH)/include/luajit-2.1/dynasm
	install deps/luajit/dynasm/*.lua \
	 	$(LUAJIT_INSTALL_PATH)/share/luajit-2.1.0-alpha/dynasm
	install deps/luajit/dynasm/*.h \
	 	$(LUAJIT_INSTALL_PATH)/include/luajit-2.1/dynasm
endif

check_luajit:
	@if [ ! -f $(LUAJIT) && ! -f deps/luajit/Makefile ]; then \
	    echo "Can't find deps/luajit/. You might need to: git submodule update --init"; exit 1; \
	fi

clean:
ifneq ("","$(wildcard deps/luajit/Makefile)")
	@(cd deps/luajit && $(MAKE) clean)
	# hardcoded, can be done better
	@rm -rf deps/.install
endif
	@(cd src; $(MAKE) clean)

.SERIAL: all
