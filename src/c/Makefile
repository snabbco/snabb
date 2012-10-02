libsnabb.so: snabb.c
	gcc -lrt -I../../../QEMU -fpic -Wall -Werror -shared -o $@ $<

clean:
	rm libsnabb.so
