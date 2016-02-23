ABS_TOP_SRCDIR:=$(shell cd $(TOP_SRCDIR) && pwd)
LUAJIT=$(ABS_TOP_SRCDIR)/deps/luajit/usr/local/bin/luajit
PATH := $(ABS_TOP_SRCDIR)/deps/luajit/usr/local/bin:$(PATH)
