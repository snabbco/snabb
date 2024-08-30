##############################################################################
# RaptorJIT Makefile. Requires GNU Make.
#
# Please read doc/install.html before changing any variables!
#
# Suitable for POSIX platforms (Linux, *BSD, OSX etc.).
# Also works with MinGW and Cygwin on Windows.
# Please check msvcbuild.bat for building with MSVC on Windows.
#
# Copyright (C) 2005-2023 Mike Pall. See Copyright Notice in luajit.h
##############################################################################

MAJVER=  1
MINVER=  0
RELVER=  0
ABIVER=  5.1
NODOTABIVER= 51

##############################################################################
#############################  COMPILER OPTIONS  #############################
##############################################################################
# These options mainly affect the speed of the JIT compiler itself, not the
# speed of the JIT-compiled code. Turn any of the optional settings on by
# removing the '#' in front of them. Make sure you force a full recompile
# with "make clean", followed by "make" if you change any options.
#
# Since the assembler part does NOT maintain a frame pointer, it's pointless
# to slow down the C part by not omitting it. Debugging, tracebacks and
# unwinding are not affected -- the assembler part has frame unwind
# information and GCC emits it where needed (x64) or with -g (see CCDEBUG).
CCOPT= -O2 -fomit-frame-pointer
# Use this if you want to generate a smaller binary (but it's slower):
#CCOPT= -Os -fomit-frame-pointer
# Note: it's no longer recommended to use -O3 with GCC 4.x.
# The I-Cache bloat usually outweighs the benefits from aggressive inlining.
#
CCDEBUG=
# Uncomment the next line to generate debug information:
#CCDEBUG= -g
#
CCWARN= -Wall
# Uncomment the next line to enable more warnings:
#CCWARN+= -Wextra -Wdeclaration-after-statement -Wredundant-decls -Wshadow -Wpointer-arith
#
##############################################################################

##############################################################################
#################################  FEATURES  #################################
##############################################################################
# Enable/disable these features as needed, but make sure you force a full
# recompile with "make clean", followed by "make".
XCFLAGS=
#
# Permanently disable the FFI extension to reduce the size of the LuaJIT
# executable. But please consider that the FFI library is compiled-in,
# but NOT loaded by default. It only allocates any memory, if you actually
# make use of it.
#XCFLAGS+= -DLUAJIT_DISABLE_FFI
#
# Features from Lua 5.2 that are unlikely to break existing code are
# enabled by default. Some other features that *might* break some existing
# code (e.g. __pairs or os.execute() return values) can be enabled here.
# Note: this does not provide full compatibility with Lua 5.2 at this time.
#XCFLAGS+= -DLUAJIT_ENABLE_LUA52COMPAT
#
# Disable the JIT compiler, i.e. turn LuaJIT into a pure interpreter.
#XCFLAGS+= -DLUAJIT_DISABLE_JIT
#
# Some architectures (e.g. PPC) can use either single-number (1) or
# dual-number (2) mode. Uncomment one of these lines to override the
# default mode. Please see LJ_ARCH_NUMMODE in lj_arch.h for details.
#XCFLAGS+= -DLUAJIT_NUMMODE=1
#XCFLAGS+= -DLUAJIT_NUMMODE=2
#
##############################################################################

##############################################################################
############################  DEBUGGING SUPPORT  #############################
##############################################################################
# Enable these options as needed, but make sure you force a full recompile
# with "make clean", followed by "make".
# Note that most of these are NOT suitable for benchmarking or release mode!
#
# Use the system provided memory allocator (realloc) instead of the
# bundled memory allocator. This is slower, but sometimes helpful for
# debugging. This option cannot be enabled on x64 without GC64, since
# realloc usually doesn't return addresses in the right address range.
# OTOH this option is mandatory for Valgrind's memcheck tool on x64 and
# the only way to get useful results from it for all other architectures.
#XCFLAGS+= -DLUAJIT_USE_SYSMALLOC
#
# This define is required to run LuaJIT under Valgrind. The Valgrind
# header files must be installed. You should enable debug information, too.
# Use --suppressions=lj.supp to avoid some false positives.
#XCFLAGS+= -DLUAJIT_USE_VALGRIND
#
# This is the client for the GDB JIT API. GDB 7.0 or higher is required
# to make use of it. See lj_gdbjit.c for details. Enabling this causes
# a non-negligible overhead, even when not running under GDB.
#XCFLAGS+= -DLUAJIT_USE_GDBJIT
#
# Turn on assertions for the Lua/C API to debug problems with lua_* calls.
# This is rather slow -- use only while developing C libraries/embeddings.
#XCFLAGS+= -DLUA_USE_APICHECK
#
# Turn on assertions for the whole LuaJIT VM. This significantly slows down
# everything. Use only if you suspect a problem with LuaJIT itself.
#XCFLAGS+= -DLUA_USE_ASSERT
#
##############################################################################
# You probably don't need to change anything below this line!
##############################################################################

##############################################################################
# Flags and options for host and target.
##############################################################################

# You can override the following variables at the make command line:
#   CC       HOST_CC       STATIC_CC       DYNAMIC_CC
#   CFLAGS   HOST_CFLAGS   TARGET_CFLAGS
#   LDFLAGS  HOST_LDFLAGS  TARGET_LDFLAGS  TARGET_SHLDFLAGS
#   LIBS     HOST_LIBS     TARGET_LIBS
#   CROSS    HOST_SYS      TARGET_SYS      TARGET_FLAGS
#
# Cross-compilation examples:
#   make HOST_CC="gcc -m32" CROSS=i586-mingw32msvc- TARGET_SYS=Windows
#   make HOST_CC="gcc -m32" CROSS=powerpc-linux-gnu-

ASOPTIONS= $(CCOPT) $(CCWARN) $(XCFLAGS) $(CFLAGS)
CCOPTIONS= $(CCDEBUG) $(ASOPTIONS)
LDOPTIONS= $(CCDEBUG) $(LDFLAGS)

HOST_CC= $(CC)
HOST_RM= rm -f
HOST_LUA=luajit

HOST_XCFLAGS= -I.
HOST_XLDFLAGS=
HOST_XLIBS=
HOST_ACFLAGS= $(CCOPTIONS) $(HOST_XCFLAGS) $(TARGET_ARCH) $(HOST_CFLAGS)
HOST_ALDFLAGS= $(LDOPTIONS) $(HOST_XLDFLAGS) $(HOST_LDFLAGS)
HOST_ALIBS= $(HOST_XLIBS) $(LIBS) $(HOST_LIBS)

STATIC_CC = $(CROSS)$(CC)
DYNAMIC_CC = $(CROSS)$(CC) -fPIC
TARGET_CC= $(STATIC_CC)
TARGET_STCC= $(STATIC_CC)
TARGET_DYNCC= $(DYNAMIC_CC)
TARGET_LD= $(CROSS)$(CC)
TARGET_AR= $(CROSS)ar rcus 2>/dev/null

TARGET_LIBPATH= $(or $(PREFIX),/usr/local)/$(or $(MULTILIB),lib)
TARGET_SONAME= libraptorjit-$(ABIVER).so.$(MAJVER)
TARGET_DYLIBNAME= libraptorjit-$(ABIVER).$(MAJVER).dylib
TARGET_DYLIBPATH= $(TARGET_LIBPATH)/$(TARGET_DYLIBNAME)
TARGET_DLLNAME= lua$(NODOTABIVER).dll
TARGET_DLLDOTANAME= libluajit-$(ABIVER).dll.a
TARGET_XSHLDFLAGS= -shared -fPIC -Wl,-soname,$(TARGET_SONAME)
TARGET_DYNXLDOPTS=

TARGET_LFSFLAGS= -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE
TARGET_XCFLAGS= $(TARGET_LFSFLAGS) -U_FORTIFY_SOURCE
TARGET_XLDFLAGS= -Wl,-E
TARGET_XLIBS= -lm
TARGET_TCFLAGS= $(CCOPTIONS) $(TARGET_XCFLAGS) $(TARGET_FLAGS) $(TARGET_CFLAGS)
TARGET_ACFLAGS= $(CCOPTIONS) $(TARGET_XCFLAGS) $(TARGET_FLAGS) $(TARGET_CFLAGS)
TARGET_ASFLAGS= $(ASOPTIONS) $(TARGET_XCFLAGS) $(TARGET_FLAGS) $(TARGET_CFLAGS)
TARGET_ALDFLAGS= $(LDOPTIONS) $(TARGET_XLDFLAGS) $(TARGET_FLAGS) $(TARGET_LDFLAGS)
TARGET_ASHLDFLAGS= $(LDOPTIONS) $(TARGET_XSHLDFLAGS) $(TARGET_FLAGS) $(TARGET_SHLDFLAGS)
TARGET_ALIBS= $(TARGET_XLIBS) $(LIBS) $(TARGET_LIBS)

TARGET_TESTARCH=$(shell $(TARGET_CC) $(TARGET_TCFLAGS) -E lj_arch.h -dM)
TARGET_LJARCH= x64

TARGET_ARCH+= $(patsubst %,-DLUAJIT_TARGET=LUAJIT_ARCH_%,$(TARGET_LJARCH))

ifneq (,$(PREFIX))
ifneq (/usr/local,$(PREFIX))
  TARGET_XCFLAGS+= -DLUA_ROOT=\"$(PREFIX)\"
  ifneq (/usr,$(PREFIX))
    TARGET_DYNXLDOPTS= -Wl,-rpath,$(TARGET_LIBPATH)
  endif
endif
endif
ifneq (,$(MULTILIB))
  TARGET_XCFLAGS+= -DLUA_MULTILIB=\"$(MULTILIB)\"
endif
ifneq (,$(LMULTILIB))
  TARGET_XCFLAGS+= -DLUA_LMULTILIB=\"$(LMULTILIB)\"
endif

##############################################################################
# Target system detection.
##############################################################################

TARGET_XCFLAGS+= -fno-stack-protector
TARGET_XLIBS+= -ldl
Host_XCFLAGS+= -DLUAJIT_OS=LUAJIT_OS_LINUX

##############################################################################
# Files and pathnames.
##############################################################################

DASM_DIR= ../dynasm
DASM= $(HOST_LUA) $(DASM_DIR)/dynasm.lua
DASM_ARCH= x64
DASM_DASC= vm_$(DASM_ARCH).dasc

BUILDVM_O= host/buildvm.o host/buildvm_asm.o \
	   host/buildvm_lib.o host/buildvm_fold.o
BUILDVM_T= host/buildvm
BUILDVM_X= $(BUILDVM_T)

HOST_O= $(BUILDVM_O)
HOST_T= $(BUILDVM_T)

LJVM_S= lj_vm.S
LJVM_O= lj_vm.o
LJVM_BOUT= $(LJVM_S)
LJVM_MODE= elfasm

LJLIB_O= lib_base.o lib_math.o lib_bit.o lib_string.o lib_table.o \
	 lib_io.o lib_os.o lib_package.o lib_debug.o lib_jit.o lib_ffi.o \
	 lib_buffer.o
LJLIB_C= $(LJLIB_O:.o=.c)

LJCORE_O= lj_assert.o lj_gc.o lj_err.o lj_char.o lj_bc.o lj_obj.o lj_buf.o \
	  lj_str.o lj_tab.o lj_func.o lj_udata.o lj_meta.o lj_debug.o \
	  lj_prng.o lj_state.o lj_dispatch.o lj_vmmath.o \
	  lj_strscan.o lj_strfmt.o lj_strfmt_num.o lj_serialize.o \
	  lj_api.o lj_vmprofile.o \
	  lj_lex.o lj_parse.o lj_bcread.o lj_bcwrite.o lj_load.o \
	  lj_ir.o lj_opt_mem.o lj_opt_fold.o lj_opt_narrow.o \
	  lj_opt_dce.o lj_opt_loop.o lj_opt_split.o lj_opt_sink.o \
	  lj_mcode.o lj_snap.o lj_record.o lj_crecord.o lj_ffrecord.o \
	  lj_asm.o lj_trace.o lj_gdbjit.o lj_auditlog.o \
	  lj_ctype.o lj_cdata.o lj_cconv.o lj_ccall.o lj_ccallback.o \
	  lj_carith.o lj_clib.o lj_cparse.o \
	  lj_lib.o lj_alloc.o lib_aux.o \
	  lj_dwarf_dwo.o \
	  $(LJLIB_O) lib_init.o

DWARF_DWO= lj_dwarf.dwo

LJVMCORE_O= $(LJVM_O) $(LJCORE_O)
LJVMCORE_DYNO= $(LJVMCORE_O:.o=_dyn.o)

LUAJIT_O= raptorjit.o
LUAJIT_A= raptorjit.a
LUAJIT_SO= libraptorjit.so
LUAJIT_T= raptorjit

ALL_T= $(LUAJIT_T) $(LUAJIT_A) $(LUAJIT_SO) $(HOST_T)
ALL_HDRGEN= lj_bcdef.h lj_ffdef.h lj_libdef.h lj_recdef.h lj_folddef.h \
	    host/buildvm_arch.h
ALL_GEN= $(LJVM_S) $(ALL_HDRGEN)
WIN_RM= *.obj *.lib *.exp *.dll *.exe *.manifest *.pdb *.ilk
ALL_RM= $(ALL_T) *.o host/*.o $(WIN_RM)

##############################################################################
# Build mode handling.
##############################################################################

TARGET_O= $(LUAJIT_A)
TARGET_T= $(LUAJIT_T) $(LUAJIT_SO)
TARGET_DEP= $(LUAJIT_SO)

Q= @
E= @echo
#Q=
#E= @:

##############################################################################
# Make targets.
##############################################################################

default all:	$(TARGET_T) $(DWARF_DWO)

clean:
	$(HOST_RM) $(ALL_RM)
	$(HOST_RM) $(ALL_GEN)

reusevm:
	cd reusevm; \
	cp -r * ../
	@echo "Copied reference VM. Ready to build."

update_reusevm:
	cp lj_bcdef.h lj_ffdef.h lj_folddef.h lj_libdef.h lj_recdef.h lj_vm.S reusevm/
	cp host/buildvm_arch.h reusevm/host/

libbc:
	./$(LUAJIT_T) host/genlibbc.lua -o host/buildvm_libbc.h $(LJLIB_C)
	$(MAKE) all

depend:
	@for file in $(ALL_HDRGEN); do \
	  test -f $$file || touch $$file; \
	  done
	@$(HOST_CC) $(HOST_ACFLAGS) -MM *.c host/*.c | \
	  sed -e "s| [^ ]*/dasm_\S*\.h||g" \
	      -e "s|^\([^l ]\)|host/\1|" \
	      -e "s| lj_target_\S*\.h| lj_target_*.h|g" \
	      -e "s| lj_emit_\S*\.h| lj_emit_*.h|g" \
	      -e "s| lj_asm_\S*\.h| lj_asm_*.h|g" >Makefile.dep
	@for file in $(ALL_HDRGEN); do \
	  test -s $$file || $(HOST_RM) $$file; \
	  done

.PHONY: default all clean libbc depend reusevm

##############################################################################
# Rules for generated files.
##############################################################################

host/buildvm_arch.h: $(DASM_DASC) $(DASM_DEP) $(DASM_DIR)/*.lua
	@command -v $(DASM) 2>/dev/null || { \
	  echo "Error: Missing dependency (luajit) for bootstrapping the VM."; \
	  echo "";                                                             \
	  echo "Here are your options to build RaptorJIT:";                    \
	  echo "  make reusevm     # copy reference VM from reusevm/";          \
	  echo "  (install luajit) # satisfy the dependency";                   \
	  echo "  nix-build        # use nix to satisfy the dependencies";      \
	  echo "";                                                             \
	  echo "Warning:";                                                     \
	  echo "  Only reusevm when running a pristine copy of RaptorJIT from";\
	  echo "  a repository that keeps the reference VM up-to-date.";       \
	  echo "  (Otherwise you might mix some stale code into your build.)"; \
	  echo;                                                                \
	  exit 1;                                                              \
	}
	$(E) "DYNASM    $@"
	$(Q)$(DASM) -o $@ $(DASM_DASC)

host/buildvm.o: $(DASM_DIR)/dasm_*.h

$(BUILDVM_T): $(BUILDVM_O)
	$(E) "HOSTLINK  $@"
	$(Q)$(HOST_CC) $(HOST_ALDFLAGS) -o $@ $(BUILDVM_O) $(HOST_ALIBS)

$(LJVM_BOUT): $(BUILDVM_T)
	$(E) "BUILDVM   $@"
	$(Q)$(BUILDVM_X) -m $(LJVM_MODE) -o $@

lj_bcdef.h: $(BUILDVM_T) $(LJLIB_C)
	$(E) "BUILDVM   $@"
	$(Q)$(BUILDVM_X) -m bcdef -o $@ $(LJLIB_C)

lj_ffdef.h: $(BUILDVM_T) $(LJLIB_C)
	$(E) "BUILDVM   $@"
	$(Q)$(BUILDVM_X) -m ffdef -o $@ $(LJLIB_C)

lj_libdef.h: $(BUILDVM_T) $(LJLIB_C)
	$(E) "BUILDVM   $@"
	$(Q)$(BUILDVM_X) -m libdef -o $@ $(LJLIB_C)

lj_recdef.h: $(BUILDVM_T) $(LJLIB_C)
	$(E) "BUILDVM   $@"
	$(Q)$(BUILDVM_X) -m recdef -o $@ $(LJLIB_C)

lj_folddef.h: $(BUILDVM_T) lj_opt_fold.c
	$(E) "BUILDVM   $@"
	$(Q)$(BUILDVM_X) -m folddef -o $@ lj_opt_fold.c

##############################################################################
# Object file rules.
##############################################################################

%.o: %.c
	$(E) "CC        $@"
	$(Q)$(TARGET_DYNCC) $(TARGET_ACFLAGS) -c -o $(@:.o=_dyn.o) $<
	$(Q)$(TARGET_CC) $(TARGET_ACFLAGS) -c -o $@ $<

%.o: %.S
	$(E) "ASM       $@"
	$(Q)$(TARGET_DYNCC) $(TARGET_ASFLAGS) -c -o $(@:.o=_dyn.o) $<
	$(Q)$(TARGET_CC) $(TARGET_ASFLAGS) -c -o $@ $<

$(LUAJIT_O):
	$(E) "CC        $@"
	$(Q)$(TARGET_STCC) $(TARGET_ACFLAGS) -c -o $@ luajit.c

$(HOST_O): %.o: %.c
	$(E) "HOSTCC    $@"
	$(Q)$(HOST_CC) $(HOST_ACFLAGS) -c -o $@ $<

$(DWARF_DWO): $(ALL_HDRGEN)

$(DWARF_DWO): %.dwo: %.c
	$(E) "CC(debug) $@"
	$(Q)$(TARGET_CC) -g3 -gdwarf-4 -gz=none -fno-eliminate-unused-debug-types -gsplit-dwarf -c $<

# Embed DWARF debug information as binary data available to raptorjit.
lj_dwarf_dwo.o lj_dwarf_dwo_dyn.o: $(DWARF_DWO)
	$(E) "EMBED     $@"
	$(Q)$(LD) -r -b binary -z noexecstack -o $@ $<
	$(Q)$(LD) -r -b binary -z noexecstack -o $(@:.o=_dyn.o) $<

include Makefile.dep

##############################################################################
# Target file rules.
##############################################################################

$(LUAJIT_A): $(LJVMCORE_O)
	$(E) "AR        $@"
	$(Q)$(TARGET_AR) $@ $(LJVMCORE_O)

# The dependency on _O, but linking with _DYNO is intentional.
$(LUAJIT_SO): $(LJVMCORE_O)
	$(E) "DYNLINK   $@"
	$(Q)$(TARGET_LD) $(TARGET_ASHLDFLAGS) -o $@ $(LJVMCORE_DYNO) $(TARGET_ALIBS)

$(LUAJIT_T): $(TARGET_O) $(LUAJIT_O) $(TARGET_DEP)
	$(E) "LINK      $@"
	$(Q)$(TARGET_LD) $(TARGET_ALDFLAGS) -o $@ $(LUAJIT_O) $(TARGET_O) $(TARGET_ALIBS)
	$(E) "OK        Successfully built RaptorJIT"

##############################################################################
