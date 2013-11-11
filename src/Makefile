Q= @
E= @echo
# For verbose command line output, uncomment these lines:
#Q=
#E= @:

SRCDIR = $(shell find . -type d -not -regex './obj.*' -printf '%P ')
OBJDIR = $(patsubst %,obj/%,$(SRCDIR))

LUASRC = $(shell find . -regex '[^\#]*\.lua' -printf '%P ')
CSRC   = $(shell find . -regex '[^\#]*\.c'   -printf '%P ')
CHDR   = $(shell find . -regex '[^\#]*\.h'   -printf '%P ')
RMSRC  = $(shell find . -name  README.md.src -printf '%P ')

LUAOBJ := $(patsubst %.lua,obj/%_lua.o,$(LUASRC))
COBJ   := $(patsubst %.c,obj/%_c.o,    $(CSRC))
HOBJ   := $(patsubst %.h,obj/%_h.o,    $(CHDR))
JITOBJS:= $(patsubst %,obj/jit_%.o,$(JITSRC))
EXTRAOBJS := obj/jit_tprof.o obj/jit_vmprof.o obj/strict.o
RMOBJS := $(patsubst %.src,%,$(RMSRC))
MDOBJS := $(patsubst %, doc/obj/%.md, $(LUASRC) $(CSRC) $(CHDR)) $(wildcard *.md)

PATH := ../deps/luajit/usr/local/bin:$(PATH)

all: snabbswitch

markdown: $(RMOBJS)

snabbswitch: $(LUAOBJ) $(HOBJ) $(COBJ)
	$(E) "LINK      $@"
	$(Q) gcc -Wl,-E -Werror -Wall -o $@ $^ \
	    ../deps/luajit/src/libluajit.a \
	    -lc -ldl -lm -lrt -lpthread -lnuma
	@echo -n "Firmware: "
	@ls -sh snabbswitch

$(OBJDIR):
	$(E) "DIR       $@"
	$(Q) mkdir -p $@

$(LUAOBJ): obj/%_lua.o: %.lua Makefile | $(OBJDIR)
	$(E) "LUA       $@"
	$(Q) luajit -bg -n $(subst /,.,$*) $< $@

$(COBJ): obj/%_c.o: %.c $(CHDR) Makefile | $(OBJDIR)
	$(E) "C         $@"
	$(Q) gcc -Wl,-E -I ../deps/luajit/src -I . -c -Wall -Werror -o $@ $<

$(HOBJ): obj/%_h.o: %.h Makefile | $(OBJDIR)
	$(E) "CHEADER   $@"
	@(echo -n "module(...,package.seeall); require(\"ffi\").cdef[=============["; \
	 cat $<; \
	 echo "]=============]") > $(basename $@).luah
	$(Q) luajit -bg -n $(subst /,.,$*)_h $(basename $@).luah $@

$(JITOBJS): obj/jit_%.o: ../deps/luajit/src/jit/%.lua $(OBJDIR)
	$(E) "LUA       $@"
	$(Q) luajit -bg -n $(patsubst obj/jit_%.o, jit.%, $@) $< $@


$(RMOBJS): %: %.src
	$(E) "MARKDOWN  $@"
	$(Q) scripts/process-markdown $< > $@

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


doc/obj/%.lua.md : %.lua Makefile
	awk '/^ *[^-]{3}/ {if (last~/^ *---/) printf("\n")} {print} {last=$$0}' < $< | sed -E -e 's/^/    /g' -e 's/^    --- ?//g' > $@

doc/obj/%.c.md : %.c Makefile
	awk '/^ *[^\/]{3}/ {if (last~/^ *\/\/\//) printf("\n")} {print} {last=$$0}' < $< | sed -E -e 's/^/    /g' -e 's|^    /// ?||g' > $@

doc/obj/%.h.md : %.h Makefile
	awk '/^ *[^\/]{3}/ {if (last~/^ *\/\/\//) printf("\n")} {print} {last=$$0}' < $< | sed -E -e 's/^/    /g' -e 's|^    /// ?||g' > $@

book: doc/snabbswitch.pdf doc/snabbswitch.html doc/snabbswitch.epub

doc/snabbswitch.md: $(MDOBJS) Makefile doc/genbook.sh
	(cd doc; ./genbook.sh) > $@

doc/snabbswitch.pdf: doc/snabbswitch.md
	$(E) "PANDOC    $@"
	$(Q) pandoc --template=doc/template.latex --latex-engine=lualatex -V fontsize=10pt -V monofont=droidsansmono -V monoscale=.70 -V verbatimspacing=.85 -V mainfont=droidserif -V sansfont=droidsans -V documentclass:book -V geometry:top=1.0in -V geometry:bottom=0.75in -S --toc --chapters  -o $@ $<

doc/snabbswitch.html doc/snabbswitch.epub: doc/snabbswitch.md
	$(E) "PANDOC    $@"
	$(Q) pandoc -S --toc --chapters -o $@ $<

CLEAN = snabbswitch obj doc/snabbswitch.* doc/obj/*.md

clean:
	$(E) "RM        $(CLEAN)"
	$(Q)-rm -rf $(CLEAN)

mrproper: clean
	$(E) "RM        $(RMOBJS)"
	$(Q)-rm -rf $(RMOBJS)

.PHONY: clean

