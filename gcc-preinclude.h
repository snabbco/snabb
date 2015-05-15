// Force an old symbol version on memcpy.
// See: http://www.win.tue.nl/~aeb/linux/misc/gcc-semibug.html
//      https://rjpower9000.wordpress.com/2012/04/09/fun-with-shared-libraries-version-glibc_2-14-not-found/

#if !defined(__ASSEMBLER__) && defined(__GLIBC__)
__asm__(".symver memcpy,memcpy@GLIBC_2.2.5");
#endif

