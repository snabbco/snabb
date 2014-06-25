
OPENONLOAD = 	$(HOME)/openonload-201310-u3

CFLAGS +=	-I$(OPENONLOAD)/src/include -std=c99 -g
LDFLAGS +=	-L$(OPENONLOAD)/build/gnu_x86_64/lib/ciul -L$(OPENONLOAD)/build/gnu_x86_64/lib/citools
LDLIBS +=	-lciul -lcitools1 -lm

all: recv send
