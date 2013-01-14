LUASRC := $(wildcard *.lua)
CSRC   := $(wildcard *.c)
CHDR   := $(wildcard *.h)

LUAOBJ := $(patsubst %.lua,obj/%.o,$(LUASRC))
COBJ   := $(patsubst %.c,obj/%.o,$(CSRC))
HOBJ   := $(patsubst %.h,obj/%_h.o,$(CHDR))

PATH := ../deps/luajit/usr/local/bin:$(PATH)

all: snabbswitch

snabbswitch: $(LUAOBJ) $(HOBJ) $(COBJ)
	gcc -Wl,-E -Werror -Wall -o $@ $^ \
	    ../deps/luafilesystem/src/lfs.o \
	    ../deps/luajit/src/libluajit.a \
	    -lc -ldl -lm -lrt
	@echo -n "Firmware: "
	@ls -sh snabbswitch

$(LUAOBJ): obj/%.o: %.lua
	luajit -bg $< $@

$(COBJ): obj/%.o: %.c $(CHDR)
	gcc -Wl,-E -I ../deps/luajit/src -c -Wall -Werror -o $@ $<

$(HOBJ): obj/%_h.o: %.h
	@echo Generating $(basename $@).lua from $< - $(basename $@)
	@(echo -n "module(...,package.seeall); require(\"ffi\").cdef[=============["; \
	 cat $<; \
	 echo "]=============]") >> $(basename $@).lua
	luajit -b $(basename $@).lua $@

clean:
	-rm snabbswitch
	-rm obj/*

