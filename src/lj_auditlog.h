/*
** Audit log. Records JIT/runtime events for offline analysis.
*/

#ifndef _LJ_AUDITLOG_H
#define _LJ_AUDITLOG_H

#include "lj_jit.h"
#include "lj_trace.h"

void lj_auditlog_trace_flush(jit_State *J);
void lj_auditlog_trace_start(jit_State *J);
void lj_auditlog_trace_stop(jit_State *J, GCtrace *T);
void lj_auditlog_trace_abort(jit_State *J, TraceError e);
void lj_auditlog_trace_record_bytecode(jit_State *J);

#endif
