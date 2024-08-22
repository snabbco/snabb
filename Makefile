##############################################################################
# RaptorJIT top level Makefile for installation. Requires GNU Make.
#
# Please read doc/install.html before changing any variables!
#
# Suitable for POSIX platforms (Linux, *BSD, OSX etc.).
# Note: src/Makefile has many more configurable options.
#
# ##### This Makefile is NOT useful for Windows! #####
# For MSVC, please follow the instructions given in src/msvcbuild.bat.
# For MinGW and Cygwin, cd to src and run make with the Makefile there.
#
# Copyright (C) 2005-2023 Mike Pall. See Copyright Notice in luajit.h
##############################################################################

MAJVER=  1
MINVER=  0
RELVER=  0
PREREL=  
VERSION= $(MAJVER).$(MINVER).$(RELVER)$(PREREL)
ABIVER=  5.1

##############################################################################
#
# Change the installation path as needed. This automatically adjusts
# the paths in src/luaconf.h, too. Note: PREFIX must be an absolute path!
#
export PREFIX= /usr/local
export MULTILIB= lib
##############################################################################

DPREFIX= $(DESTDIR)$(PREFIX)
INSTALL_BIN=   $(DPREFIX)/bin
INSTALL_LIB=   $(DPREFIX)/$(MULTILIB)
INSTALL_SHARE= $(DPREFIX)/share
INSTALL_DEFINC= $(DPREFIX)/include/raptorjit-$(MAJVER).$(MINVER)
INSTALL_INC=   $(INSTALL_DEFINC)

INSTALL_LJLIBD= $(INSTALL_SHARE)/raptorjit-$(VERSION)
INSTALL_JITLIB= $(INSTALL_LJLIBD)/jit
INSTALL_PKGCONFIG= $(INSTALL_LIB)/pkgconfig

INSTALL_TNAME= raptorjit-$(VERSION)
INSTALL_TSYMNAME= raptorjit
INSTALL_ANAME= libraptorjit-$(ABIVER).a
INSTALL_SOSHORT1= libraptorjit-$(ABIVER).so
INSTALL_SOSHORT2= libraptorjit-$(ABIVER).so.$(MAJVER)
INSTALL_SONAME= $(INSTALL_SOSHORT2).$(MINVER).$(RELVER)
INSTALL_DYLIBSHORT1= libraptorjit-$(ABIVER).dylib
INSTALL_DYLIBSHORT2= libraptorjit-$(ABIVER).$(MAJVER).dylib
INSTALL_DYLIBNAME= libraptorjit-$(ABIVER).$(MAJVER).$(MINVER).$(RELVER).dylib
INSTALL_PCNAME= raptorjit.pc

INSTALL_STATIC= $(INSTALL_LIB)/$(INSTALL_ANAME)
INSTALL_DYN= $(INSTALL_LIB)/$(INSTALL_SONAME)
INSTALL_SHORT1= $(INSTALL_LIB)/$(INSTALL_SOSHORT1)
INSTALL_SHORT2= $(INSTALL_LIB)/$(INSTALL_SOSHORT2)
INSTALL_T= $(INSTALL_BIN)/$(INSTALL_TNAME)
INSTALL_TSYM= $(INSTALL_BIN)/$(INSTALL_TSYMNAME)
INSTALL_PC= $(INSTALL_PKGCONFIG)/$(INSTALL_PCNAME)

INSTALL_DIRS= $(INSTALL_BIN) $(INSTALL_LIB) $(INSTALL_INC) \
 $(INSTALL_JITLIB)
UNINSTALL_DIRS= $(INSTALL_JITLIB) $(INSTALL_LJLIBD) $(INSTALL_INC)

RM= rm -f
MKDIR= mkdir -p
RMDIR= rmdir 2>/dev/null
SYMLINK= ln -sf
INSTALL_X= install -m 0755
INSTALL_F= install -m 0644
UNINSTALL= $(RM)
LDCONFIG= ldconfig -n 2>/dev/null
SED_PC= sed -e "s|^prefix=.*|prefix=$(PREFIX)|" \
	    -e "s|^multilib=.*|multilib=$(MULTILIB)|" \
	    -e "s|^relver=.*|relver=$(RELVER)|"
ifneq ($(INSTALL_DEFINC),$(INSTALL_INC))
  SED_PC+= -e "s|^includedir=.*|includedir=$(INSTALL_INC)|"
endif

FILE_T= raptorjit
FILE_A= libraptorjit.a
FILE_SO= libraptorjit.so
FILE_PC= raptorjit.pc
FILES_INC= lua.h lualib.h lauxlib.h luaconf.h lua.hpp luajit.h
FILES_JITLIB= bc.lua bcsave.lua vmdef.lua

ifeq (,$(findstring Windows,$(OS)))
  HOST_SYS:= $(shell uname -s)
else
  HOST_SYS= Windows
endif
TARGET_SYS?= $(HOST_SYS)

ifeq (Darwin,$(TARGET_SYS))
  INSTALL_SONAME= $(INSTALL_DYLIBNAME)
  INSTALL_SOSHORT1= $(INSTALL_DYLIBSHORT1)
  INSTALL_SOSHORT2= $(INSTALL_DYLIBSHORT2)
  LDCONFIG= :
endif

##############################################################################

INSTALL_DEP= src/raptorjit

default all $(INSTALL_DEP):
	@echo "==== Building RaptorJIT $(VERSION) ===="
	$(MAKE) -C src
	@echo "==== Successfully built RaptorJIT $(VERSION) ===="

reusevm:
	$(MAKE) -C src reusevm

install: $(INSTALL_DEP)
	@echo "==== Installing RaptorJIT $(VERSION) to $(PREFIX) ===="
	$(MKDIR) $(INSTALL_DIRS)
	cd src && $(INSTALL_X) $(FILE_T) $(INSTALL_T)
	cd src && test -f $(FILE_A) && $(INSTALL_F) $(FILE_A) $(INSTALL_STATIC) || :
	$(RM) $(INSTALL_DYN) $(INSTALL_SHORT1) $(INSTALL_SHORT2)
	cd src && test -f $(FILE_SO) && \
	  $(INSTALL_X) $(FILE_SO) $(INSTALL_DYN) && \
	  ( $(LDCONFIG) $(INSTALL_LIB) || : ) && \
	  $(SYMLINK) $(INSTALL_SONAME) $(INSTALL_SHORT1) && \
	  $(SYMLINK) $(INSTALL_SONAME) $(INSTALL_SHORT2) || :
	cd etc && $(SED_PC) $(FILE_PC) > $(FILE_PC).tmp && \
	  $(INSTALL_F) -D $(FILE_PC).tmp $(INSTALL_PC) && \
	  $(RM) $(FILE_PC).tmp
	cd src && $(INSTALL_F) $(FILES_INC) $(INSTALL_INC)
	cd src/jit && $(INSTALL_F) $(FILES_JITLIB) $(INSTALL_JITLIB)
	$(SYMLINK) $(INSTALL_TNAME) $(INSTALL_TSYM)
	@echo "==== Successfully installed LuaJIT $(VERSION) to $(PREFIX) ===="

uninstall:
	@echo "==== Uninstalling RaptorJIT $(VERSION) from $(PREFIX) ===="
	$(UNINSTALL) $(INSTALL_T) $(INSTALL_STATIC) $(INSTALL_DYN) $(INSTALL_SHORT1) $(INSTALL_SHORT2)
	for file in $(FILES_JITLIB); do \
	  $(UNINSTALL) $(INSTALL_JITLIB)/$$file; \
	  done
	for file in $(FILES_INC); do \
	  $(UNINSTALL) $(INSTALL_INC)/$$file; \
	  done
	$(LDCONFIG) $(INSTALL_LIB)
	$(RMDIR) $(UNINSTALL_DIRS) || :
	@echo "==== Successfully uninstalled RaptorJIT $(VERSION) from $(PREFIX) ===="

##############################################################################

clean:
	$(MAKE) -C src clean

bootstrapclean:
	$(MAKE) -C src bootstrapclean

.PHONY: all install clean

##############################################################################
