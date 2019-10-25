/*
** Audit log. Records JIT/runtime events for offline analysis.
*/

#define lj_auditlog_c

#include <stdio.h>
#include <time.h>

#include "lj_trace.h"
#include "lj_ctype.h"
#include "lj_auditlog.h"
#include "lj_debuginfo.h"

/* Maximum data to buffer in memory before file is opened. */
#define MAX_MEM_BUFFER 10*1024*1024
/* State for initial in-memory stream. */
static char *membuffer;
static size_t membuffersize;

static FILE *fp;    /* File where the audit log is written. */
static int error;   /* Have we been unable to initialize the log? */
static int open;    /* are we logging to a real file? */
static size_t loggedbytes; /* Bytes already written to log. */
static size_t sizelimit;  /* File size when logging will stop.  */
#define DEFAULT_SIZE_LIMIT 100*1024*1024 /* Generous size limit. */

/* -- byte counting file write wrappers ----------------------------------- */

static int cfputc(int c, FILE *f) {
  loggedbytes++;
  return fputc(c, f);
}

static int cfputs(const char *s, FILE *f) {
  loggedbytes += strlen(s);
  return fputs(s, f);
}

static int cfwrite(const void *ptr, size_t size, size_t nmemb, FILE *f) {
  loggedbytes += size * nmemb;
  return fwrite(ptr, size, nmemb, f);
}

/* -- msgpack writer - see http://msgpack.org/index.html ------------------ */
/* XXX assumes little endian cpu. */

static void fixmap(int size) {
  cfputc(0x80|size, fp);         /* map header with size */
};

static void str_16(const char *s) {
  uint16_t biglen = __builtin_bswap16(strlen(s));
  cfputc(0xda, fp);                        /* string header */
  cfwrite(&biglen, sizeof(biglen), 1, fp); /* string length */
  cfputs(s, fp);                           /* string contents */
}

static void uint_64(uint64_t n) {
  uint64_t big = __builtin_bswap64(n);
  cfputc(0xcf, fp);                  /* uint 64 header */
  cfwrite(&big, sizeof(big), 1, fp); /* value */
}

static void bin_32(const void *ptr, int n) {
  uint32_t biglen = __builtin_bswap32(n);
  cfputc(0xc6, fp);                        /* array 32 header */
  cfwrite(&biglen, sizeof(biglen), 1, fp); /* length */
  cfwrite(ptr, n, 1, fp);                  /* data */
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
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  lua_assert(nattributes <= 252);
  fixmap(nattributes+3);
  str_16("nanotime");  /* = */ uint_64(ts.tv_sec * 1000000000LL + ts.tv_nsec);
  str_16("type");      /* = */ str_16("event");
  str_16("event");     /* = */ str_16(type);
  /* Caller fills in the further nattributes... */
}

static void log_blob(const char *name, const char *ptr, int size) {
  fixmap(3);
  str_16("type"); /* = */ str_16("blob");
  str_16("name"); /* = */ str_16(name);
  str_16("data"); /* = */ bin_32(ptr, size);
}

/* Log objects that define the virtual machine. */
static void lj_auditlog_vm_definitions()
{
  log_mem("lj_ir_mode", (void*)&lj_ir_mode, sizeof(lj_ir_mode));
  log_blob("lj_dwarf.dwo", &_binary_lj_dwarf_dwo_start, &_binary_lj_dwarf_dwo_end - &_binary_lj_dwarf_dwo_start);
}

/* Check that the log is open before logging a message. */
static int ensure_log_started() {
  if (fp != NULL) {
    if (loggedbytes < sizelimit) {
      return 1;
    } else {
      /* Log has grown to size limit. */
      log_event("auditlog_size_limit_reached", 0);
      fclose(fp);
      fp = NULL;
      error = 1;
      return 0;
    }
  }
  if (fp != NULL) return 1;     /* Log already open? */
  if (error) return 0;          /* Log has already errored? */
  /* Start logging into a memory buffer. The entries will be migrated
  ** onto disk when (if) a file system path is provided.
  ** (We want the log to be complete even if it is opened after some
  ** JIT activity has ocurred.)
  */
  if ((fp = open_memstream(&membuffer, &membuffersize)) != NULL) {
    lj_auditlog_vm_definitions();
    sizelimit = MAX_MEM_BUFFER;
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
int lj_auditlog_open(const char *path, size_t maxsize)
{
  FILE *newfp;
  if (open || error) return 0; /* Sorry, too late... */
  sizelimit = maxsize ? maxsize : DEFAULT_SIZE_LIMIT;
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
  IRRef ref;
  log_mem("MCode[]", T->mcode, T->szmcode);
  log_mem("SnapShot[]", T->snap, T->nsnap * sizeof(*T->snap));
  log_mem("SnapEntry[]", T->snapmap, T->nsnapmap * sizeof(*T->snapmap));
  log_mem("IRIns[]", &T->ir[T->nk], (T->nins - T->nk + 1) * sizeof(IRIns));
  log_mem("uint16_t[]", T->szirmcode, T->nszirmcode * sizeof(uint16_t));
  for (ref = T->nk; ref < REF_TRUE; ref++) {
    IRIns *ir = &T->ir[ref];
    if (ir->o == IR_KGC) {
      GCobj *o = ir_kgc(ir);
      /* Log referenced string constants. For e.g. HREFK table keys. */
      switch (o->gch.gct) {
      case ~LJ_TSTR:
      case ~LJ_TFUNC:
        log_GCobj(o);
        break;
      }
    }
    if (irt_is64(ir->t) && ir->o != IR_KNULL) {
      /* Skip over 64-bit inline operand for this instruction. */
      ref++;
    }
  }
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

static void log_GCfunc(GCfunc *f)
{
  log_mem("GCfunc", f, sizeof(*f));
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
  case ~LJ_TFUNC:
    log_GCfunc((GCfunc *)o);
  }
}

/* API functions */

/* Log a trace that has just been compiled. */
void lj_auditlog_trace_stop(jit_State *J, GCtrace *T)
{
  if (ensure_log_started()) {
    log_GCtrace(T);
    log_jit_State(J);
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

void lj_auditlog_new_ctypeid(CTypeID id, const char *desc)
{
  if (ensure_log_started()) {
    log_event("new_ctypeid", 2);
    str_16("id");   /* = */ uint_64(id);
    str_16("desc"); /* = */ str_16(desc);
  }
}

