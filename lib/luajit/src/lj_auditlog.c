/*
** Audit log. Records JIT/runtime events for offline analysis.
*/

#define lj_auditlog_c

#include <stdio.h>

#include "lj_trace.h"
#include "lj_auditlog.h"

/* Maximum data to buffer in memory before file is opened. */
#define MAX_MEM_BUFFER 1024*1024
/* State for initial in-memory stream. */
static char *membuffer;
static size_t membuffersize;

static FILE *fp;    /* File where the audit log is written. */
static int error;   /* Have we been unable to initialize the log? */
static int open;    /* are we logging to a real file? */

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

/* Log a snapshot of an object in memory. */
static void log_mem(const char *type, void *ptr, unsigned int size) {
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

/* Log objects that define the virtual machine. */
void lj_auditlog_vm_definitions()
{
  log_mem("lj_ir_mode", (void*)&lj_ir_mode, sizeof(lj_ir_mode));
}

/* Check that the log is open before logging a message. */
static int ensure_log_started() {
  if (fp != NULL) return 1;     /* Log already open? */
  if (error) return 0;          /* Log has already errored? */
  /* Start logging into a memory buffer. The entries will be migrated
  ** onto disk when (if) a file system path is provided.
  ** (We want the log to be complete even if it is opened after some
  ** JIT activity has ocurred.)
  */
  if ((fp = open_memstream(&membuffer, &membuffersize)) != NULL) {
    lj_auditlog_vm_definitions();
    return 1;
  } else {
    error = 1;
    return 0;
  }
}

/* Open the auditlog at a new path.
** Migrate in-memory log onto file.
** Can only open once.
** Return zero on failure.
*/
int lj_auditlog_open(const char *path)
{
  FILE *newfp;
  if (open) return 0; /* Sorry, already opened... */
  if (!ensure_log_started()) return 0;
  newfp = fopen(path, "wb+");
  /* Migrate log entries from memory buffer. */
  fflush(fp);
  if (fwrite(membuffer, 1, membuffersize, newfp) != membuffersize) return 0;
  fp = newfp;
  open = 1;
  return 1;
}

/* -- high-level LuaJIT object logging ------------------------------------ */

static void log_GCobj(GCobj *o);

static void log_jit_State(jit_State *J)
{
  log_mem("BCRecLog[]", J->bclog, J->nbclog * sizeof(*J->bclog));
  log_mem("jit_State", J, sizeof(*J));
}

static void log_GCtrace(GCtrace *T)
{
  log_mem("MCode[]", T->mcode, T->szmcode);
  log_mem("SnapShot[]", T->snap, T->nsnap * sizeof(*T->snap));
  log_mem("SnapEntry[]", T->snapmap, T->nsnapmap * sizeof(*T->snapmap));
  log_mem("IRIns[]", &T->ir[T->nk], (T->nins - T->nk + 1) * sizeof(IRIns));
  log_mem("GCtrace", T, sizeof(*T));
}

static void log_GCproto(GCproto *pt)
{
  log_GCobj(gcref(pt->chunkname));
  log_mem("GCproto", pt, pt->sizept); /* includes colocated arrays */
}

static void log_GCstr(GCstr *s)
{
  log_mem("GCstr", s, sizeof(*s) + s->len);
}

static void log_GCobj(GCobj *o)
{
  /* Log some kinds of objects (could be fancier...) */
  switch (o->gch.gct) {
  case ~LJ_TPROTO:
    log_GCproto((GCproto *)o);
    break;
  case ~LJ_TTRACE:
    log_GCtrace((GCtrace *)o);
    break;
  case ~LJ_TSTR:
    log_GCstr((GCstr *)o);
    break;
  }
}

/* API functions */

/* Log a trace that has just been compiled. */
void lj_auditlog_trace_stop(jit_State *J, GCtrace *T)
{
  if (ensure_log_started()) {
    log_jit_State(J);
    log_GCtrace(T);
    log_event("trace_stop", 2);
    str_16("GCtrace");   /* = */ uint_64((uint64_t)T);
    str_16("jit_State"); /* = */ uint_64((uint64_t)J);
  }
}

void lj_auditlog_trace_abort(jit_State *J, TraceError e)
{
  if (ensure_log_started()) {
    log_jit_State(J);
    log_event("trace_abort", 2);
    str_16("TraceError"); /* = */ uint_64(e);
    str_16("jit_State");  /* = */ uint_64((uint64_t)J);
  }
}

void lj_auditlog_lex(const char *chunkname, const char *s, int sz)
{
  if (ensure_log_started()) {
    log_mem("char[]", (void*)s, sz);
    log_event("lex", 2);
    str_16("chunkname"); /* = */ str_16(chunkname);
    str_16("source");    /* = */ bin_32((void*)s, sz);
  }
}

void lj_auditlog_new_prototype(GCproto *pt)
{
  if (ensure_log_started()) {
    log_GCproto(pt);
    log_event("new_prototype", 1);
    str_16("GCproto"); /* = */ uint_64((uint64_t)pt);;
  }
}

void lj_auditlog_trace_flushall(jit_State *J)
{
  if (ensure_log_started()) {
    log_jit_State(J);
    log_event("trace_flushall", 1);
    str_16("jit_State");  /* = */ uint_64((uint64_t)J);
  }
}

