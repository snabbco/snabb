LUAJIT := ../deps/luajit/src/luajit

LUASRC := $(wildcard lua/*.lua)
CSRC   := $(wildcard c/*.c)
CHDR   := $(wildcard c/*.h)

LUAOBJ := $(patsubst lua/%.lua,obj/%.o,$(LUASRC))
COBJ   := $(patsubst c/%.c,obj/%.o,$(CSRC))

all: snabbswitch
	@echo -n "Firmware: "
	@ls -sh snabbswitch

snabbswitch: $(LUAOBJ) $(COBJ)
	gcc -Wl,-E -Werror -Wall -o $@ $^ \
	    ../deps/luafilesystem/src/lfs.o \
	    ../deps/luajit/src/libluajit.a \
	    -lc -ldl -lm -lrt

$(LUAOBJ): obj/%.o: lua/%.lua
	$(LUAJIT) -b $< $@

$(COBJ): obj/%.o: c/%.c $(CHDR)
	gcc -I ../deps/luajit/src -c -Wall -Werror -o $@ $<

clean:
	-rm snabbswitch
	-rm obj/*

