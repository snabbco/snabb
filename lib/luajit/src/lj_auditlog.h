/*
** Audit log. Records JIT/runtime events for offline analysis.
*/

#ifndef _LJ_AUDITLOG_H
#define _LJ_AUDITLOG_H

#include "lj_jit.h"
#include "lj_trace.h"
#include "lj_ctype.h"

int lj_auditlog_open(const char *path, size_t maxsize);

void lj_auditlog_new_prototype(GCproto *pt);
void lj_auditlog_lex(const char *chunkname, const char *s, int sz);
void lj_auditlog_trace_flushall(jit_State *J);
void lj_auditlog_trace_stop(jit_State *J, GCtrace *T);
void lj_auditlog_trace_abort(jit_State *J, TraceError e);
void lj_auditlog_new_ctypeid(CTypeID id, const char *desc);

#endif
