#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

void
errchk(int code, char *msg)
{
  if (code != 0) {
    perror(msg);
    exit(1);
  }
}

void
fatal(char *fmt, ...)
{
  va_list args;

  va_start(args, fmt);
  vfprintf(stderr, fmt, args);
  va_end(args);
  fflush(stderr);
  exit(-1);
}
