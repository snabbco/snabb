/*
** Audit log. Records JIT/runtime events for offline analysis.
*/

#define lj_auditlog_c

#include <stdio.h>

#include "lj_auditlog.h"

/* File where the audit log is written. */
FILE *fp;

/* -- msgpack writer - see http://msgpack.org/index.html ------------------ */

/* XXX assumes little endian cpu. */

static void fixmap(int size) {
  fputc(0x80|size, fp);         /* map header with size */
};

static void str_16(const char *s) {
  uint16_t biglen = __builtin_bswap16(strlen(s));
  fputc(0xda, fp);                        /* string header */
  fwrite(&biglen, sizeof(biglen), 1, fp); /* string length */
  fputs(s, fp);                           /* string contents */
}

static void uint_64(uint64_t n) {
  uint64_t big = __builtin_bswap64(n);
  fputc(0xcf, fp);                  /* uint 64 header */
  fwrite(&big, sizeof(big), 1, fp); /* value */
}

static void bin_32(void *ptr, int n) {
  uint32_t biglen = __builtin_bswap32(n);
  fputc(0xc6, fp);                        /* array 32 header */
  fwrite(&biglen, sizeof(biglen), 1, fp); /* length */
  fwrite(ptr, n, 1, fp);                  /* data */
}

/* -- low-level object logging API ---------------------------------------- */

/* Ensure that the log file is open. */
static void ensure_log_open()
{
  if (!fp) {
    fp = fopen("audit.log", "w");
    lua_assert(fp != NULL);
  }
}

/* Log a snapshot of an object in memory. */
static void log(const char *type, void *ptr, unsigned int size)
{
  ensure_log_open();
  fixmap(5);
  str_16("type");    /* = */ str_16("memory");
  str_16("hint");    /* = */ str_16(type);
  str_16("address"); /* = */ uint_64((uint64_t)ptr);
  str_16("size");    /* = */ uint_64(size);
  str_16("data");    /* = */ bin_32(ptr, size);
}

/* -- high-level LuaJIT object logging ------------------------------------ */

/* Log a trace that has just been compiled. */
void lj_auditlog_trace_stop(jit_State *J, GCtrace *T)
{
  /* Log the memory containing the GCtrace object and other important
     memory that it references. */
  log("GCtrace", T, sizeof(*T));
  log("MCode[]", T->mcode, T->szmcode);
  log("SnapShot[]", T->snap, T->nsnap * sizeof(*T->snap));
  log("SnapEntry[]", T->snapmap, T->nsnapmap * sizeof(*T->snapmap));
}

