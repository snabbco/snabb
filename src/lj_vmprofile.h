/*
** Virtual machine profiling.
** Copyright (C) 2017 Luke Gorrie. See Copyright Notice in luajit.h
*/

#ifndef _LJ_VMPROFILE_H
#define _LJ_VMPROFILE_H

#include <stdint.h>
#include "lj_obj.h"

/* Counters are 64-bit to avoid overflow even in long running processes. */
typedef uint64_t VMProfileCount;

/* Maximum trace number for distinct counter buckets. Traces with
   higher numbers will be counted together in a shared overflow bucket. */
#define LJ_VMPROFILE_TRACE_MAX 4096

/* Complete set of counters for VM and traces. */
typedef struct VMProfile {
  uint32_t magic;               /* 0x1d50f007 */
  uint16_t major, minor;        /* 4, 0 */
  /* Profile counters are stored in a 2D matrix of count[trace][state].
  **
  ** The profiler attempts to attribute each sample to one vmstate and
  ** one trace. The vmstate is an LJ_VMST_* constant. The trace is
  ** either 1..4096 (counter for one individual trace) or 0 (shared
  ** counter for all higher-numbered traces and for samples that can't
  ** be attributed to a specific trace at all.)
  **/
  VMProfileCount count[LJ_VMPROFILE_TRACE_MAX+1][LJ_VMST__MAX];
} VMProfile;

/* Functions that should be accessed via FFI. */

void *vmprofile_open_file(const char *filename);
void vmprofile_set_profile(void *counters);
int vmprofile_get_profile_size();

#endif
