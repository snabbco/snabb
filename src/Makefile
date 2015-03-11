Q= @
E= @echo
# For verbose command line output, uncomment these lines:
#Q=
#E= @:

# Required submodule versions.
# Defined here to detect version mismatches at build time.
LUAJIT_VSN    := "v2.0.3-328-g04dc64b"
LJSYSCALL_VSN := "v0.10-65-g7081d97"

TEST_SKIPPED="43"

SRCDIR = $(shell find . -type d -not -regex './obj.*' -printf '%P ')
OBJDIR = $(patsubst %,obj/%,$(SRCDIR))

LUASRC = $(shell find . -regex '[^\#]*\.lua' -printf '%P ')
CSRC   = $(shell find . -regex '[^\#]*\.c'   -printf '%P ')
CHDR   = $(shell find . -regex '[^\#]*\.h'   -printf '%P ')
ASM    = $(shell find . -regex '[^\#]*\.dasc' -printf '%P ')
RMSRC  = $(shell find . -name  README.md.src -printf '%P ')
# regexp is to include program/foo but not program/foo/bar
PROGRAM = $(shell find program -regex '^[^/]+/[^/]+' -type d -printf '%P ')
INCSRC = $(shell find . -regex '[^\#]*\.inc' -printf '%P ')

LUAOBJ := $(patsubst %.lua,obj/%_lua.o,$(LUASRC))
COBJ   := $(patsubst %.c,obj/%_c.o,    $(CSRC))
HOBJ   := $(patsubst %.h,obj/%_h.o,    $(CHDR))
ASMOBJ := $(patsubst %.dasc,obj/%_dasc.o,   $(ASM))
JITOBJS:= $(patsubst %,obj/jit_%.o,$(JITSRC))
EXTRAOBJS := obj/jit_tprof.o obj/jit_vmprof.o obj/strict.o
RMOBJS := $(patsubst %.src,%,$(RMSRC))
INCOBJ := $(patsubst %.inc,obj/%_inc.o, $(INCSRC))
EXE    := bin/snabb $(patsubst %,bin/%,$(PROGRAM))

# TESTMODS expands to:
#   core.memory core.lib ...
# for each module that has a top-level selftest () function.
TESTMODS = $(shell find . -regex '[^\#]*\.lua' -printf '%P ' | \
             xargs grep -l '^function selftest *[[:punct:]]' | \
             sed -e 's_\.lua__' -e 's_/_._g')

# TESTSCRIPTS expands to:
#   lib/watchdog/selftest.sh ...
# for each executable selftext.sh script in src.
TESTSCRIPTS = $(shell find . -name "selftest.sh" -executable | xargs)

PATH := ../deps/luajit/usr/local/bin:$(PATH)

snabb: $(LUAOBJ) $(HOBJ) $(COBJ) $(ASMOBJ) $(INCOBJ) $(LUAJIT_A)
	$(E) "SUBMODULES"
	@if grep -vqF $(LUAJIT_VSN)    ../deps/luajit.vsn || \
	    grep -vqF $(LJSYSCALL_VSN) ../deps/ljsyscall.vsn; then \
	    echo "Error: Submodule version mismatch"			>&2; \
	    echo "luajit:"						>&2; \
	    echo "  require: $(LUAJIT_VSN)"				>&2; \
	    echo "  found:   $(shell cat ../deps/luajit.vsn)"		>&2; \
	    echo "ljsyscall:"						>&2; \
	    echo "  require: $(LJSYSCALL_VSN)"				>&2; \
	    echo "  found:   $(shell cat ../deps/ljsyscall.vsn) "	>&2; \
	    echo "Please update and rebuild submodules."		>&2; \
	    echo ""							>&2; \
	    echo "Cheat sheet:"						>&2; \
	    echo "  cd snabbswitch"					>&2; \
	    echo "  git submodule update"				>&2; \
	    echo "  make clean"						>&2; \
	    echo "  make -j"						>&2; \
	    echo ""							>&2; \
	    exit 1; \
	 fi
	$(E) "LINK      $@"
	$(Q) gcc -Wl,--no-as-needed -Wl,-E -Werror -Wall -o $@ $^ \
	    ../deps/luajit/src/libluajit.a \
	    -lrt -lc -ldl -lm -lpthread
	@echo -n "BINARY    "
	@ln -fs snabb snabbswitch
	@ls -sh snabb

all: $(EXE)

$(EXE): snabb
	$(E) "PROGRAM   $@"
	$(Q) install -D snabb $@

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

$(OBJDIR) bin testlog:
	$(E) "DIR       $@"
	$(Q) mkdir -p $@

$(LUAOBJ): obj/%_lua.o: %.lua Makefile | $(OBJDIR)
	$(E) "LUA       $@"
	$(Q) luajit -bg -n $(subst /,.,$*) $< $@

$(COBJ): obj/%_c.o: %.c $(CHDR) Makefile | $(OBJDIR)
	$(E) "C         $@"
	$(Q) gcc -Wl,-E -I ../deps/luajit/src -I . -include $(CURDIR)/../gcc-preinclude.h -c -Wall -Werror -o $@ $<

obj/lib/checksum_c.o: lib/checksum.c
	$(E) "C(O2)     $@"
	$(Q) gcc -O2 -mavx2 -msse2 -Wl,-E -I ../deps/luajit/src -I . -include $(CURDIR)/../gcc-preinclude.h -c -Wall -Werror -o $@ $<

$(HOBJ): obj/%_h.o: %.h Makefile | $(OBJDIR)
	$(E) "H         $@"
	@(echo -n "module(...,package.seeall); require(\"ffi\").cdef[=============["; \
	 cat $<; \
	 echo "]=============]") > $(basename $@).luah
	$(Q) luajit -bg -n $(subst /,.,$*)_h $(basename $@).luah $@

$(ASMOBJ): obj/%_dasc.o: %.dasc $(CHDR) Makefile | $(OBJDIR)
	$(E) "ASM       $@"
	$(Q) luajit ../deps/luajit/dynasm/dynasm.lua -o $@.gen $<
	$(Q) gcc -Wl,-E -I ../deps/luajit/src -I . -I ../deps/luajit -c -Wall -Werror -x c -o $@ $@.gen

$(JITOBJS): obj/jit_%.o: ../deps/luajit/src/jit/%.lua $(OBJDIR)
	$(E) "LUA       $@"
	$(Q) luajit -bg -n $(patsubst obj/jit_%.o, jit.%, $@) $< $@


$(RMOBJS): %: %.src
	$(E) "MARKDOWN  $@"
	$(Q) scripts/process-markdown $< > $@

$(INCOBJ): obj/%_inc.o: %.inc Makefile | $(OBJDIR)
	$(E) "INC       $@"
	@(echo -n "return [=============["; \
	 cat $<; \
	 echo "]=============]") > $(basename $@).luainc
	$(Q) luajit -bg -n $(subst /,.,$*)_inc $(basename $@).luainc $@

# extra/ third party bits and pieces
obj/strict.o: extra/strict.lua | $(OBJDIR)
	$(E) "LUA       $@"
	$(Q) luajit -bg $< $@

obj/jit_tprof.o: extra/tprof.lua | $(OBJDIR)
	$(E) "LUA       $@"
	$(Q) luajit -bg -n jit.tprof $< $@

obj/jit_vmprof.o: extra/vmprof.c | $(OBJDIR)
	$(E) "C         $@"
	$(Q) gcc -Wl,-E -O2 -I ../deps/luajit/src -c -Wall -Werror -o $@ $<

book: doc/snabbswitch.pdf doc/snabbswitch.html doc/snabbswitch.epub

doc/snabbswitch.md: markdown Makefile doc/genbook.sh
	(cd doc; ./genbook.sh) > $@

doc/snabbswitch.pdf: doc/snabbswitch.md
	$(E) "PANDOC    $@"
	$(Q) (cd doc; pandoc --template=template.latex --latex-engine=lualatex -V fontsize=10pt -V monofont=droidsansmono -V monoscale=.70 -V verbatimspacing=.85 -V mainfont=droidserif -V sansfont=droidsans -V documentclass:book -V geometry:top=1.0in -V geometry:bottom=0.75in -S --toc --chapters  -o snabbswitch.pdf snabbswitch.md)

doc/snabbswitch.html: doc/snabbswitch.md
	$(E) "PANDOC    $@"
	$(Q) (cd doc; pandoc --self-contained --css="style.css" -S -s --toc --chapters -o snabbswitch.html snabbswitch.md)

doc/snabbswitch.epub: doc/snabbswitch.md
	$(E) "PANDOC    $@"
	$(Q) (cd doc; pandoc --self-contained --css="style.css" -S -s --toc --chapters -o snabbswitch.epub snabbswitch.md)

CLEAN = snabb snabbswitch obj bin doc/snabbswitch.* doc/.images/* testlog

clean:
	$(E) "RM        $(CLEAN)"
	$(Q)-rm -rf $(CLEAN)

mrproper: clean
	$(E) "RM        $(RMOBJS)"
	$(Q)-rm -rf $(RMOBJS)

.PHONY: clean $(TESTMODS) $(TESTSCRIPTS)

