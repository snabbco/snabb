all: lib1.so lib11.so lib2.so lib21.so -lib2.so

lib1.so: lib1.c
	gcc -Wall -O2 -I../../ -ansi -shared -o lib1.so lib1.c

lib11.so: lib11.c
	gcc -Wall -O2 -I../../ -ansi -shared -o lib11.so lib11.c

lib2.so: lib2.c
	gcc -Wall -O2 -I../../ -ansi -shared -o lib2.so lib2.c

lib21.so: lib21.c
	gcc -Wall -O2 -I../../ -ansi -shared -o lib21.so lib21.c

-lib2.so: lib2.so
	cp lib2.so ./-lib2.so
