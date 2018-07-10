ABS_TOP_SRCDIR:=$(shell cd $(TOP_SRCDIR) && pwd)
LUAJIT=$(ABS_TOP_SRCDIR)/deps/luajit/usr/local/bin/luajit
PATH := $(ABS_TOP_SRCDIR)/deps/luajit/usr/local/bin:$(PATH)
export LUA_PATH := $(ABS_TOP_SRCDIR)/deps/dynasm/?.lua;;
export LD_LIBRARY_PATH := $(ABS_TOP_SRCDIR)/deps/dynasm:$(LD_LIBARARY_PATH)
