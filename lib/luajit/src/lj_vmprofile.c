/*
** VM profiling.
** Copyright (C) 2016 Luke Gorrie. See Copyright Notice in luajit.h
*/

#define lj_vmprofile_c
#define LUA_CORE

#define _GNU_SOURCE 1
#include <stdio.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdint.h>
#include <signal.h>
#include <ucontext.h>
#undef _GNU_SOURCE

#include "lj_err.h"
#include "lj_obj.h"
#include "lj_dispatch.h"
#include "lj_jit.h"
#include "lj_trace.h"
#include "lj_vmprofile.h"

static struct {
  global_State *g;
  struct sigaction oldsa;
} state;

static int started;

static VMProfile *profile;      /* Current counters */

/* -- Signal handler ------------------------------------------------------ */

/* Signal handler: bumps one counter. */
static void vmprofile_signal(int sig, siginfo_t *si, void *data)
{
  if (profile != NULL) {
    int vmstate, trace;     /* sample matrix indices */
    lua_State *L = gco2th(gcref(state.g->cur_L));
    /*
     * The basic job of this function is to select the right indices
     * into the profile counter matrix. That requires deciding which
     * logical state the VM is in and which trace the sample should be
     * attributed to. Heuristics are needed to pick appropriate values.
     */
    if (state.g->vmstate > 0) {    /* Running JIT mcode. */
      GCtrace *T = traceref(L2J(L), (TraceNo)state.g->vmstate);
      intptr_t ip = (intptr_t)((ucontext_t*)data)->uc_mcontext.gregs[REG_RIP];
      ptrdiff_t mcposition = ip - (intptr_t)T->mcode;
      if ((mcposition < 0) || (mcposition >= T->szmcode)) {
        vmstate = LJ_VMST_FFI;    /* IP is outside the trace mcode. */
      } else if ((T->mcloop != 0) && (mcposition >= T->mcloop)) {
        vmstate = LJ_VMST_LOOP;   /* IP is inside the mcode loop. */
      } else {
        vmstate = LJ_VMST_HEAD;   /* IP is inside mcode but not loop. */
      }
      trace = state.g->vmstate;
    } else {                    /* Running VM code (not JIT mcode.) */
      if (~state.g->vmstate == LJ_VMST_GC && state.g->gcvmstate > 0) {
        /* Special case: GC invoked from JIT mcode. */
        vmstate = LJ_VMST_JGC;
        trace = state.g->gcvmstate;
      } else {
        /* General case: count towards most recently exited trace. */
        vmstate = ~state.g->vmstate;
        trace = state.g->lasttrace;
      }
    }
    /* Handle overflow from individual trace counters. */
    trace = trace <= LJ_VMPROFILE_TRACE_MAX ? trace : 0;
    /* Phew! We have calculated the indices and now we can bump the counter. */
    lua_assert(vmstate >= 0 && vmstate <= LJ_VMST__MAX);
    lua_assert(trace >= 0 && trace <= LJ_VMPROFILE_TRACE_MAX);
    profile->count[trace][vmstate]++;
  }
}

static void start_timer(int interval)
{
  struct itimerval tm;
  struct sigaction sa;
  tm.it_value.tv_sec = tm.it_interval.tv_sec = interval / 1000;
  tm.it_value.tv_usec = tm.it_interval.tv_usec = (interval % 1000) * 1000;
  setitimer(ITIMER_VIRTUAL, &tm, NULL);
  sa.sa_flags = SA_SIGINFO | SA_RESTART;
  sa.sa_sigaction = vmprofile_signal;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGVTALRM, &sa, &state.oldsa);
}

static void stop_timer()
{
  struct itimerval tm;
  tm.it_value.tv_sec = tm.it_interval.tv_sec = 0;
  tm.it_value.tv_usec = tm.it_interval.tv_usec = 0;
  setitimer(ITIMER_VIRTUAL, &tm, NULL);
  sigaction(SIGVTALRM, NULL, &state.oldsa);
}

/* -- State that the application can manage via FFI ----------------------- */

/* How much memory to allocate for profiler counters. */
int vmprofile_get_profile_size() {
  return sizeof(VMProfile);
}

/* Open a counter file on disk and returned the mmapped data structure. */
void *vmprofile_open_file(const char *filename)
{
  int fd;
  void *ptr = MAP_FAILED;
  if (((fd = open(filename, O_RDWR|O_CREAT, 0666)) != -1) &&
      ((ftruncate(fd, sizeof(VMProfile))) != -1) &&
      ((ptr = mmap(NULL, sizeof(VMProfile), PROT_READ|PROT_WRITE,
                   MAP_SHARED, fd, 0)) != MAP_FAILED)) {
    memset(ptr, 0, sizeof(VMProfile));
  }
  if (fd != -1) close(fd);
  return ptr == MAP_FAILED ? NULL : ptr;
}

/* Set the memory where the next samples will be counted. 
   Size of the memory must match vmprofile_get_profile_size(). */
void vmprofile_set_profile(void *counters) {
  profile = (VMProfile*)counters;
  profile->magic = 0x1d50f007;
  profile->major = 4;
  profile->minor = 0;
}

void vmprofile_start(lua_State *L)
{
  if (!started) {
    memset(&state, 0, sizeof(state));
    state.g = G(L);
    start_timer(1);               /* Sample every 1ms */
    started = 1;
  }
}

void vmprofile_stop()
{
  stop_timer();
  started = 0;
}

/* -- Lua API ------------------------------------------------------------- */

LUA_API int luaJIT_vmprofile_open(lua_State *L, const char *str, int noselect, int nostart)
{
  void *ptr;
  if ((ptr = vmprofile_open_file(str)) != NULL) {
    setlightudV(L->base, checklightudptr(L, ptr));
    if (!noselect) vmprofile_set_profile(ptr);
    if (!nostart) vmprofile_start(L);
  } else {
    setnilV(L->base);
  }
  return 1;
}

LUA_API int luaJIT_vmprofile_close(lua_State *L, void *ud)
{
  munmap(ud, sizeof(VMProfile));
  return 0;
}

LUA_API int luaJIT_vmprofile_select(lua_State *L, void *ud)
{
  setlightudV(L->base, checklightudptr(L, profile));
  vmprofile_set_profile(ud);
  return 1;
}

LUA_API int luaJIT_vmprofile_start(lua_State *L)
{
  vmprofile_start(L);
  return 0;
}

LUA_API int luaJIT_vmprofile_stop(lua_State *L)
{
  vmprofile_stop();
  return 0;
}

