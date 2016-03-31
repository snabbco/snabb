LINK = BASIC_LINK #FF_LINK
CFLAGS = -D_GNU_SOURCE -pthread -D$(LINK) -std=c99 -g -O
OBJS = pipeline.o fan.o threadprocs.o utils.o main.o

linktest: $(OBJS) linktest.h basic.h ff.h
	cc $(CFLAGS) -o linktest $(OBJS)

clean:
	rm -f $(OBJS) linktest

$(OBJS): linktest.h 

