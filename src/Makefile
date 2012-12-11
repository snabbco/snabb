LUAJIT := ../deps/luajit/src/luajit

LUASRC := $(wildcard *.lua)
CSRC   := $(wildcard *.c)
CHDR   := $(wildcard *.h)

LUAOBJ := $(patsubst %.lua,obj/%.o,$(LUASRC))
COBJ   := $(patsubst %.c,obj/%.o,$(CSRC))
HOBJ   := $(patsubst %.h,obj/%_h.o,$(CHDR))

all: snabbswitch
	@echo -n "Firmware: "
	@ls -sh snabbswitch

snabbswitch: $(LUAOBJ) $(COBJ) $(HOBJ)
	gcc -Wl,-E -Werror -Wall -o $@ $^ \
	    ../deps/luafilesystem/src/lfs.o \
	    ../deps/luajit/src/libluajit.a \
	    -lc -ldl -lm -lrt

$(LUAOBJ): obj/%.o: %.lua
	$(LUAJIT) -b $< $@

$(COBJ): obj/%.o: %.c $(CHDR)
	gcc -I ../deps/luajit/src -c -Wall -Werror -o $@ $<

$(HOBJ): obj/%_h.o: %.h
	echo Generating $@.lua from $<
	@(echo -n "module(...,package.seeall); require(\"ffi\").cdef[=============["; \
	 cat $<; \
	 echo "]=============]") >> $@.lua
	$(LUAJIT) -b $@.lua $@

clean:
	-rm snabbswitch
	-rm obj/*

