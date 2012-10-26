LUAJIT := ../deps/luajit/src/luajit

LUASRC := $(wildcard *.lua)
CSRC   := $(wildcard *.c)
CHDR   := $(wildcard *.h)

LUAOBJ := $(patsubst %.lua,obj/%.o,$(LUASRC))
COBJ   := $(patsubst %.c,obj/%.o,$(CSRC))

all: snabbswitch
	@echo -n "Firmware: "
	@ls -sh snabbswitch

snabbswitch: $(LUAOBJ) $(COBJ)
	gcc -Wl,-E -Werror -Wall -o $@ $^ \
	    ../deps/luafilesystem/src/lfs.o \
	    ../deps/luajit/src/libluajit.a \
	    -lc -ldl -lm -lrt

$(LUAOBJ): obj/%.o: %.lua
	$(LUAJIT) -b $< $@

$(COBJ): obj/%.o: %.c $(CHDR)
	gcc -I ../deps/luajit/src -c -Wall -Werror -o $@ $<

clean:
	-rm snabbswitch
	-rm obj/*

