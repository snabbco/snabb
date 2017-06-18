/*
** Audit log. Records JIT/runtime events for offline analysis.
*/

#define lj_auditlog_c

#include <stdio.h>

#include "lj_trace.h"
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
static void ensure_log_open() {
  if (!fp) {
    fp = fopen("audit.log", "w");
    lua_assert(fp != NULL);
  }
}

/* Log a snapshot of an object in memory. */
static void log_mem(const char *type, void *ptr, unsigned int size) {
  ensure_log_open();
  fixmap(4);
  str_16("type");    /* = */ str_16("memory");
  str_16("hint");    /* = */ str_16(type);
  str_16("address"); /* = */ uint_64((uint64_t)ptr);
  str_16("data");    /* = */ bin_32(ptr, size);
}

static void log_event(const char *type, int nattributes) {
  lua_assert(nattributes <= 253);
  fixmap(nattributes+2);
  str_16("type");  /* = */ str_16("event");
  str_16("event"); /* = */ str_16(type);
  /* Caller fills in the further nattributes... */
}

/* -- high-level LuaJIT object logging ------------------------------------ */

/* Log a trace that has just been compiled. */
void lj_auditlog_trace_stop(jit_State *J, GCtrace *T)
{
  log_mem("GCtrace", T, sizeof(*T));
  log_mem("MCode[]", T->mcode, T->szmcode);
  log_mem("SnapShot[]", T->snap, T->nsnap * sizeof(*T->snap));
  log_mem("SnapEntry[]", T->snapmap, T->nsnapmap * sizeof(*T->snapmap));
  log_mem("IRIns[]", &T->ir[T->nk], (T->nins - T->nk + 1) * sizeof(IRIns));
  log_event("trace_stop", 1);
  str_16("GCtrace"); /* = */ uint_64((uint64_t)T);
}

void lj_auditlog_trace_abort(jit_State *J, TraceError e) {
  log_mem("jit_State", J, sizeof(*J));
  log_event("trace_abort", 2);
  str_16("jit_State");  /* = */ uint_64((uint64_t)J);
  str_16("TraceError"); /* = */ uint_64(e);
}

