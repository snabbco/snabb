LUASRC := $(wildcard *.lua)
CSRC   := $(wildcard *.c)
CHDR   := $(wildcard *.h)
# Import jit.* modules from LuaJIT.
JITSRC := v bc bcsave dump vmdef dis_x86 dis_x64

LUAOBJ := $(patsubst %.lua,obj/lua_%.o,$(LUASRC))
COBJ   := $(patsubst %.c,obj/%.o,$(CSRC))
HOBJ   := $(patsubst %.h,obj/%_h.o,$(CHDR))
JITOBJS:= $(patsubst %,obj/jit_%.o,$(JITSRC))
EXTRAOBJS := obj/jit_tprof.o obj/jit_vmprof.o obj/strict.o
MDOBJS := $(patsubst %, doc/obj/%.md, $(LUASRC) $(CSRC) $(CHDR)) $(wildcard *.md)

PATH := ../deps/luajit/usr/local/bin:$(PATH)

all: snabbswitch

snabbswitch: $(LUAOBJ) $(HOBJ) $(COBJ) $(JITOBJS) $(EXTRAOBJS)
	gcc -Wl,-E -Werror -Wall -o $@ $^ \
	    ../deps/luajit/src/libluajit.a \
	    -lc -ldl -lm -lrt -lpthread
	@echo -n "Firmware: "
	@ls -sh snabbswitch

$(LUAOBJ): obj/lua_%.o: %.lua Makefile
	luajit -bg $< $@

$(COBJ): obj/%.o: %.c $(CHDR) Makefile
	gcc -Wl,-E -I ../deps/luajit/src -c -Wall -Werror -o $@ $<

$(HOBJ): obj/%_h.o: %.h Makefile
	@echo Generating $(basename $@).lua from $< - $(basename $@)
	@(echo -n "module(...,package.seeall); require(\"ffi\").cdef[=============["; \
	 cat $<; \
	 echo "]=============]") > $(basename $@).lua
	luajit -b $(basename $@).lua $@

$(JITOBJS): obj/jit_%.o: ../deps/luajit/src/jit/%.lua
	luajit -bg -n $(patsubst obj/jit_%.o, jit.%, $@) $< $@


# extra/ third party bits and pieces
obj/strict.o: extra/strict.lua
	luajit -bg $< $@

obj/jit_tprof.o: extra/tprof.lua
	luajit -bg -n jit.tprof $< $@

obj/jit_vmprof.o: extra/vmprof.c
	gcc -Wl,-E -O2 -I ../deps/luajit/src -c -Wall -Werror -o $@ $<

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
	pandoc --template=doc/template.latex --latex-engine=lualatex -V fontsize=10pt -V monofont=droidsansmono -V monoscale=.70 -V verbatimspacing=.85 -V mainfont=droidserif -V sansfont=droidsans -V documentclass:book -V geometry:top=1.0in -V geometry:bottom=0.75in -S --toc --chapters  -o $@ $<

doc/snabbswitch.html doc/snabbswitch.epub: doc/snabbswitch.md
	pandoc -S --toc --chapters -o $@ $<

clean:
	-rm snabbswitch
	-rm obj/*
	-rm doc/snabbswitch.*
	-rm doc/obj/*.md
