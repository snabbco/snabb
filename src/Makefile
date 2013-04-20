LUASRC := $(wildcard *.lua)
CSRC   := $(wildcard *.c)
CHDR   := $(wildcard *.h)
# Import jit.* modules from LuaJIT.
JITSRC := v bc bcsave dump vmdef dis_x86 dis_x64

LUAOBJ := $(patsubst %.lua,obj/%.o,$(LUASRC))
COBJ   := $(patsubst %.c,obj/%.o,$(CSRC))
HOBJ   := $(patsubst %.h,obj/%_h.o,$(CHDR))
JITOBJS:= $(patsubst %,obj/jit_%.o,$(JITSRC))

PATH := ../deps/luajit/usr/local/bin:$(PATH)

all: snabbswitch

snabbswitch: $(LUAOBJ) $(HOBJ) $(COBJ) $(JITOBJS)
	gcc -Wl,-E -Werror -Wall -o $@ $^ \
	    ../deps/luajit/src/libluajit.a \
	    -lc -ldl -lm -lrt
	@echo -n "Firmware: "
	@ls -sh snabbswitch

$(LUAOBJ): obj/%.o: %.lua Makefile
	luajit -bg $< $@

$(COBJ): obj/%.o: %.c $(CHDR) Makefile
	gcc -Wl,-E -I ../deps/luajit/src -c -Wall -Werror -o $@ $<

$(HOBJ): obj/%_h.o: %.h Makefile
	@echo Generating $(basename $@).lua from $< - $(basename $@)
	@(echo -n "module(...,package.seeall); require(\"ffi\").cdef[=============["; \
	 cat $<; \
	 echo "]=============]") >> $(basename $@).lua
	luajit -b $(basename $@).lua $@

$(JITOBJS): obj/jit_%.o: ../deps/luajit/src/jit/%.lua
	luajit -bg -n $(patsubst obj/jit_%.o, jit.%, $@) $< $@

clean:
	-rm snabbswitch
	-rm obj/*

