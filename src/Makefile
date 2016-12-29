Q= @
E= @echo
# For verbose command line output, uncomment these lines:
#Q=
#E= @:

export TEST_SKIPPED=43
CC ?= gcc

SRCDIR = $(shell find . -type d -not -regex './obj.*' -printf '%P ')
OBJDIR = $(patsubst %,obj/%,$(SRCDIR))

LUASRC = $(shell find . -regex '[^\#]*\.lua' -printf '%P ')
PFLUASRC = $(shell cd ../lib/pflua/src && \
	         find . -regex '[^\#]*\.lua' -printf '%P ')
CSRC   = $(shell find . -regex '[^\#]*\.c' -not -regex './arch/.*' -printf '%P ')
CHDR   = $(shell find . -regex '[^\#]*\.h' -printf '%P ')
ASM    = $(shell find . -regex '[^\#]*\.dasl' -printf '%P ')
ARCHSRC= $(shell find . -regex '^./arch/[^\#]*\.c' -printf '%P ')
RMSRC  = $(shell find . -name '*.md' -not -regex './obj.*' -printf '%P ')
# regexp is to include program/foo but not program/foo/bar
PROGRAM = $(shell find program -regex '^[^/]+/[^/]+' -type d -printf '%P ')
# sort to eliminate potential duplicate of programs.inc
INCSRC = $(sort $(shell find . -regex '[^\#]*\.inc' -printf '%P ') programs.inc)
YANGSRC= $(shell find . -regex '[^\#]*\.yang' -printf '%P ')

LUAOBJ := $(patsubst %.lua,obj/%_lua.o,$(LUASRC))
PFLUAOBJ := $(patsubst %.lua,obj/%_lua.o,$(PFLUASRC))
COBJ   := $(patsubst %.c,obj/%_c.o,    $(CSRC))
HOBJ   := $(patsubst %.h,obj/%_h.o,    $(CHDR))
ARCHOBJ:= $(patsubst %.c,obj/%_c.o,    $(ARCHSRC))
ASMOBJ := $(patsubst %.dasl,obj/%_dasl.o,   $(ASM))
JITOBJS:= $(patsubst %,obj/jit_%.o,$(JITSRC))
EXTRAOBJS := obj/jit_tprof.o obj/jit_vmprof.o obj/strict.o
RMOBJS := $(patsubst %,obj/%,$(RMSRC))
INCOBJ := $(patsubst %.inc,obj/%_inc.o, $(INCSRC))
YANGOBJ:= $(patsubst %.yang,obj/%_yang.o, $(YANGSRC))
EXE    := bin/snabb $(patsubst %,bin/%,$(PROGRAM))

# TESTMODS expands to:
#   core.memory core.lib ...
# for each module that has a top-level selftest () function.
TESTMODS = $(shell find . -regex '[^\#]*\.\(lua\|dasl\)' -printf '%P ' | \
             xargs grep -s -l '^function selftest *[[:punct:]]' | \
             sed -e 's_\.lua__' -e 's_\.dasl__' -e 's_/_._g')

# TESTSCRIPTS expands to:
#   lib/watchdog/selftest.sh ...
# for each executable selftext.sh script in src.
TESTSCRIPTS = $(shell find . -name "selftest.sh" -executable | xargs)

PATH := ../lib/luajit/usr/local/bin:$(PATH)

snabb: $(LUAOBJ) $(PFLUAOBJ) $(HOBJ) $(COBJ) $(ARCHOBJ) $(ASMOBJ) $(INCOBJ) $(YANGOBJ) $(LUAJIT_A)
	$(E) "LINK      $@"
	$(Q) $(CC) $(DEBUG) -Wl,--no-as-needed -Wl,-E -Werror -Wall -o $@ $^ \
	    ../lib/luajit/src/libluajit.a \
	    -lrt -lc -ldl -lm -lpthread
	@echo -n "BINARY    "
	@ls -sh snabb

all: $(EXE)

# Rebuild after git submodules are updated.
submods:
	(cd ..; git submodule update; make clean; make)

$(EXE): snabb bin
	$(E) "COMPRESS  $@"
	$(Q) upx -f --brute -o$@ snabb
	@echo -n "BINARY    "
	@ls -sh $@

markdown: $(RMOBJS)

test: $(TESTMODS) $(TESTSCRIPTS)

test_ci: FAIL_ON_FIRST="true"

test_ci: $(TESTMODS) $(TESTSCRIPTS)

$(TESTMODS): testlog snabb
	$(E) "TEST      $@"
	$(Q) ./snabb snsh -t $@ > testlog/$@ 2>&1 || ( \
		EXITCODE="$$?"; \
		[ "$$EXITCODE" -eq $(TEST_SKIPPED) ] \
		&& ( \
			echo "SKIPPED   testlog/$@"; \
			echo "EXITCODE: $$EXITCODE" >> testlog/$@; \
		) \
		|| ( \
			echo "ERROR     testlog/$@"; \
			echo "EXITCODE: $$EXITCODE" >> testlog/$@; \
			if [ -n "$(FAIL_ON_FIRST)" ]; then exit $$EXITCODE; fi;\
		) \
	)

testlog = testlog/$(shell echo "$(@)" | sed -e 's_/_._g')
$(TESTSCRIPTS): testlog snabb
	$(E) "TEST      $@"
	$(Q) ./$@ > $(testlog) 2>&1 || ( \
		EXITCODE="$$?"; \
		[ "$$EXITCODE" -eq $(TEST_SKIPPED) ] \
		&& ( \
			echo "SKIPPED   $(testlog)"; \
			echo "EXITCODE: $$EXITCODE" >> $(testlog); \
		) \
		|| ( \
			echo "ERROR     $(testlog)"; \
			echo "EXITCODE: $$EXITCODE" >> $(testlog); \
			if [ -n "$(FAIL_ON_FIRST)" ]; then exit $$EXITCODE; fi;\
		) \
	)

$(OBJDIR) bin testlog $(OBJDIR/doc):
	$(E) "DIR       $@"
	$(Q) mkdir -p $@

$(LUAOBJ): obj/%_lua.o: %.lua Makefile | $(OBJDIR)
	$(E) "LUA       $@"
	$(Q) luajit -bg -n $(subst /,.,$*) $< $@

$(PFLUAOBJ): obj/%_lua.o: ../lib/pflua/src/%.lua Makefile
	$(E) "LUA       $@"
	$(Q) mkdir -p $(dir $@)
	$(Q) luajit -bg -n $(subst /,.,$*) $< $@

$(COBJ): obj/%_c.o: %.c $(CHDR) Makefile | $(OBJDIR)
	$(E) "C         $@"
	$(Q) $(CC) $(DEBUG) -Wl,-E -I ../lib/luajit/src -I . -include $(CURDIR)/../gcc-preinclude.h -c -Wall -Werror -o $@ $<

obj/arch/avx2_c.o: arch/avx2.c Makefile
	$(E) "C(AVX2)   $@"
	$(Q) $(CC) -O2 -mavx2 $(DEBUG) -Wl,-E -I ../lib/luajit/src -I . -include $(CURDIR)/../gcc-preinclude.h -c -Wall -Werror -o $@ $<

obj/arch/sse2_c.o: arch/sse2.c Makefile
	$(E) "C(SSE2)   $@"
	$(Q) $(CC) -O2 -msse2 $(DEBUG) -Wl,-E -I ../lib/luajit/src -I . -include $(CURDIR)/../gcc-preinclude.h -c -Wall -Werror -o $@ $<

$(HOBJ): obj/%_h.o: %.h Makefile | $(OBJDIR)
	$(E) "H         $@"
	@(echo -n "module(...,package.seeall); require(\"ffi\").cdef[=============["; \
	 cat $<; \
	 echo "]=============]") > $(basename $@).luah
	$(Q) luajit -bg -n $(subst /,.,$*)_h $(basename $@).luah $@

$(ASMOBJ): obj/%_dasl.o: %.dasl $(CHDR) Makefile | $(OBJDIR)
	$(E) "ASM       $@"
	$(Q) luajit dynasm.lua -o $@.gen $<
	$(Q) luajit -bg -n $(subst /,.,$*) $@.gen $@

$(JITOBJS): obj/jit_%.o: ../lib/luajit/src/jit/%.lua $(OBJDIR)
	$(E) "LUA       $@"
	$(Q) luajit -bg -n $(patsubst obj/jit_%.o, jit.%, $@) $< $@

$(RMOBJS): obj/%: %
	$(E) "MARKDOWN  $@"
	$(Q) scripts/process-markdown $< $@

$(INCOBJ): obj/%_inc.o: %.inc Makefile | $(OBJDIR)
	$(E) "INC       $@"
	@(echo -n "return [=============["; \
	 cat $<; \
	 echo "]=============]") > $(basename $@).luainc
	$(Q) luajit -bg -n $(subst /,.,$*)_inc $(basename $@).luainc $@

$(YANGOBJ): obj/%_yang.o: %.yang Makefile | $(OBJDIR)
	$(E) "YANG      $@"
	@(echo -n "return [=============["; \
	 cat $<; \
	 echo "]=============]") > $(basename $@).luayang
	$(Q) luajit -bg -n $(subst /,.,$*)_yang $(basename $@).luayang $@

# Create list of programs that exist
programs.inc: program
	@(for d in program/*/; do basename $$d; done) > $@

FORCE:

# extra/ third party bits and pieces
obj/strict.o: extra/strict.lua | $(OBJDIR)
	$(E) "LUA       $@"
	$(Q) luajit -bg $< $@

obj/jit_tprof.o: extra/tprof.lua | $(OBJDIR)
	$(E) "LUA       $@"
	$(Q) luajit -bg -n jit.tprof $< $@

obj/jit_vmprof.o: extra/vmprof.c | $(OBJDIR)
	$(E) "C         $@"
	$(Q) $(CC) $(DEBUG) -Wl,-E -O2 -I ../lib/luajit/src -c -Wall -Werror -o $@ $<

book: obj/doc/snabb.pdf obj/doc/snabb.html obj/doc/snabb.epub

obj/doc/snabb.markdown: markdown Makefile doc/genbook.sh
	(cd doc; ./genbook.sh) > $@

obj/doc/snabb.pdf: obj/doc/snabb.markdown
	$(E) "PANDOC    $@"
	$(Q) (cd obj/doc; pandoc --template=../../doc/template.latex --latex-engine=lualatex -V fontsize=10pt -V monofont=droidsansmono -V monoscale=.70 -V verbatimspacing=.85 -V mainfont=droidserif -V sansfont=droidsans -V documentclass:book -V geometry:top=1.0in -V geometry:bottom=0.75in -S --toc --chapters  -o ../../$@ ../../$<)

obj/doc/snabb.html: obj/doc/snabb.markdown
	$(E) "PANDOC    $@"
	$(Q) (cd obj/doc; pandoc --self-contained --css="../../doc/style.css" -S -s --toc --chapters -o ../../$@ ../../$<)

obj/doc/snabb.epub: obj/doc/snabb.markdown
	$(E) "PANDOC    $@"
	$(Q) (cd obj/doc; pandoc --self-contained --css="../../doc/style.css" -S -s --toc --chapters -o ../../$@ ../../$<)

CLEAN = snabb obj bin testlog programs.inc

clean:
	$(E) "RM        $(CLEAN)"
	$(Q)-rm -rf $(CLEAN)

mrproper: clean
	$(E) "RM        $(RMOBJS)"
	$(Q)-rm -rf $(RMOBJS)

benchmarks:
	$(Q) (scripts/bench.sh)

.PHONY: clean $(TESTMODS) $(TESTSCRIPTS) benchmarks

