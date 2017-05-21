/*
** Audit log. Records JIT/runtime events for offline analysis.
*/

#define lj_auditlog_c

#include <stdio.h>

#include "lj_auditlog.h"

FILE *fp;

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
  fprintf(fp, "type=%s address=%p size=%d data:\n", type, ptr, size);
  fwrite(ptr, size, 1, fp);
}

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

