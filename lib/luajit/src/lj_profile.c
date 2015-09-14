/*
** Low-overhead profiling.
** Copyright (C) 2005-2015 Mike Pall. See Copyright Notice in luajit.h
*/

#define lj_profile_c
#define LUA_CORE
#define _GNU_SOURCE 1

#include "lj_obj.h"

#if LJ_HASPROFILE

#include "lj_buf.h"
#include "lj_frame.h"
#include "lj_debug.h"
#include "lj_dispatch.h"
#if LJ_HASJIT
#include "lj_jit.h"
#include "lj_trace.h"
#endif
#include "lj_profile.h"

#include "luajit.h"

#if LJ_PROFILE_SIGPROF

#include <sys/time.h>
#include <signal.h>
#define profile_lock(ps)	UNUSED(ps)
#define profile_unlock(ps)	UNUSED(ps)

#if 1
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/syscall.h>
#include <sys/ioctl.h>
#include <linux/perf_event.h>
#include <sys/prctl.h>
#endif


#elif LJ_PROFILE_PTHREAD

#include <pthread.h>
#include <time.h>
#if LJ_TARGET_PS3
#include <sys/timer.h>
#endif
#define profile_lock(ps)	pthread_mutex_lock(&ps->lock)
#define profile_unlock(ps)	pthread_mutex_unlock(&ps->lock)

#elif LJ_PROFILE_WTHREAD

#define WIN32_LEAN_AND_MEAN
#if LJ_TARGET_XBOX360
#include <xtl.h>
#include <xbox.h>
#else
#include <windows.h>
#endif
typedef unsigned int (WINAPI *WMM_TPFUNC)(unsigned int);
#define profile_lock(ps)	EnterCriticalSection(&ps->lock)
#define profile_unlock(ps)	LeaveCriticalSection(&ps->lock)

#endif

/* Profiler state. */
typedef struct ProfileState {
  global_State *g;		/* VM state that started the profiler. */
  luaJIT_profile_callback cb;	/* Profiler callback. */
  void *data;			/* Profiler callback data. */
  SBuf sb;			/* String buffer for stack dumps. */
  int interval;			/* Sample interval in milliseconds. */
  int samples;			/* Number of samples for next callback. */
  char *flavour;		/* What generates profiling events. */
  int perf_event_fd;		/* Performace event file descriptor */
  int vmstate;			/* VM state when profile timer triggered. */
#if LJ_PROFILE_SIGPROF
  struct sigaction oldsa;	/* Previous SIGPROF state. */
#elif LJ_PROFILE_PTHREAD
  pthread_mutex_t lock;		/* g->hookmask update lock. */
  pthread_t thread;		/* Timer thread. */
  int abort;			/* Abort timer thread. */
#elif LJ_PROFILE_WTHREAD
#if LJ_TARGET_WINDOWS
  HINSTANCE wmm;		/* WinMM library handle. */
  WMM_TPFUNC wmm_tbp;		/* WinMM timeBeginPeriod function. */
  WMM_TPFUNC wmm_tep;		/* WinMM timeEndPeriod function. */
#endif
  CRITICAL_SECTION lock;	/* g->hookmask update lock. */
  HANDLE thread;		/* Timer thread. */
  int abort;			/* Abort timer thread. */
#endif
} ProfileState;

/* Sadly, we have to use a static profiler state.
**
** The SIGPROF variant needs a static pointer to the global state, anyway.
** And it would be hard to extend for multiple threads. You can still use
** multiple VMs in multiple threads, but only profile one at a time.
*/
static ProfileState profile_state;

/* Default sample interval in milliseconds. */
#define LJ_PROFILE_INTERVAL_DEFAULT	10

/* -- Profiler/hook interaction ------------------------------------------- */

#if !LJ_PROFILE_SIGPROF
void LJ_FASTCALL lj_profile_hook_enter(global_State *g)
{
  ProfileState *ps = &profile_state;
  if (ps->g) {
    profile_lock(ps);
    hook_enter(g);
    profile_unlock(ps);
  } else {
    hook_enter(g);
  }
}

void LJ_FASTCALL lj_profile_hook_leave(global_State *g)
{
  ProfileState *ps = &profile_state;
  if (ps->g) {
    profile_lock(ps);
    hook_leave(g);
    profile_unlock(ps);
  } else {
    hook_leave(g);
  }
}
#endif

/* -- Profile callbacks --------------------------------------------------- */

/* Callback from profile hook (HOOK_PROFILE already cleared). */
void LJ_FASTCALL lj_profile_interpreter(lua_State *L)
{
  ProfileState *ps = &profile_state;
  global_State *g = G(L);
  uint8_t mask;
  profile_lock(ps);
  mask = (g->hookmask & ~HOOK_PROFILE);
  if (!(mask & HOOK_VMEVENT)) {
    int samples = ps->samples;
    ps->samples = 0;
    g->hookmask = HOOK_VMEVENT;
    lj_dispatch_update(g);
    profile_unlock(ps);
    ps->cb(ps->data, L, samples, ps->vmstate);  /* Invoke user callback. */
    profile_lock(ps);
    mask |= (g->hookmask & HOOK_PROFILE);
  }
  g->hookmask = mask;
  lj_dispatch_update(g);
  profile_unlock(ps);
}

/* Trigger profile hook. Asynchronous call from OS-specific profile timer. */
static void profile_trigger(ProfileState *ps)
{
  global_State *g = ps->g;
  uint8_t mask;
  profile_lock(ps);
  ps->samples++;  /* Always increment number of samples. */
  mask = g->hookmask;
  if (!(mask & (HOOK_PROFILE|HOOK_VMEVENT))) {  /* Set profile hook. */
    int st = g->vmstate;
    ps->vmstate = st >= 0 ? 'N' :
		  st == ~LJ_VMST_INTERP ? 'I' :
		  st == ~LJ_VMST_C ? 'C' :
		  st == ~LJ_VMST_GC ? 'G' : 'J';
    g->hookmask = (mask | HOOK_PROFILE);
    lj_dispatch_update(g);
  }
  profile_unlock(ps);
}

/* -- OS-specific profile timer handling ---------------------------------- */

#if LJ_PROFILE_SIGPROF

/* SIGPROF handler. */
static void profile_signal(int sig)
{
  UNUSED(sig);
  profile_trigger(&profile_state);
}


static int perf_event_open(struct perf_event_attr *attr,
			   pid_t pid, int cpu, int group_fd,
			   unsigned long flags)
{
  return syscall(SYS_perf_event_open, attr, pid, cpu, group_fd, flags);
}


static void register_prof_events(ProfileState *ps)
{
  struct flavour_t {
    char *name; uint32_t type; uint64_t config;
  };

  static struct flavour_t flavours[] =
      {
	{ "sw-cpu-clock",
	  PERF_TYPE_SOFTWARE, PERF_COUNT_SW_CPU_CLOCK },

	{ "sw-context-switches",
	  PERF_TYPE_SOFTWARE, PERF_COUNT_SW_CONTEXT_SWITCHES },

	{ "sw-page-faults",
	  PERF_TYPE_SOFTWARE, PERF_COUNT_SW_PAGE_FAULTS },

	{ "sw-minor-page-faults",
	  PERF_TYPE_SOFTWARE, PERF_COUNT_SW_PAGE_FAULTS_MIN },

	{ "sw-major-page-faults",
	  PERF_TYPE_SOFTWARE, PERF_COUNT_SW_PAGE_FAULTS_MAJ },

	{ "branch-instructions",
	  PERF_TYPE_HARDWARE, PERF_COUNT_HW_BRANCH_INSTRUCTIONS },

	{ "cpu-cycles",
	  PERF_TYPE_HARDWARE, PERF_COUNT_HW_CPU_CYCLES },

	{ "instructions",
	  PERF_TYPE_HARDWARE, PERF_COUNT_HW_INSTRUCTIONS },

	{ "cache-references",
	  PERF_TYPE_HARDWARE, PERF_COUNT_HW_CACHE_REFERENCES },

	{ "cache-misses",
	  PERF_TYPE_HARDWARE, PERF_COUNT_HW_CACHE_MISSES },

	{ "branch-instructions",
	  PERF_TYPE_HARDWARE, PERF_COUNT_HW_BRANCH_INSTRUCTIONS },

	{ "branch-misses",
	  PERF_TYPE_HARDWARE, PERF_COUNT_HW_BRANCH_MISSES },

	{ "bus-cycles",
	  PERF_TYPE_HARDWARE, PERF_COUNT_HW_BUS_CYCLES },

	{ "stalled-cycles-frontend",
	  PERF_TYPE_HARDWARE, PERF_COUNT_HW_STALLED_CYCLES_FRONTEND },

	{ "stalled-cycles-backend",
	  PERF_TYPE_HARDWARE, PERF_COUNT_HW_STALLED_CYCLES_BACKEND },

	{ "cpu-cycles",
	  PERF_TYPE_HARDWARE, PERF_COUNT_HW_REF_CPU_CYCLES },

	{ 0, 0, 0 }
  };


  struct perf_event_attr attr = { };

  memset(&attr, 0, sizeof(struct perf_event_attr));

  const struct flavour_t *f;
  for (f = flavours; f->name != 0; f++)
    {
      if (strcmp (ps->flavour, f->name) == 0)
	{
	  attr.type = f->type;
	  attr.config = f->config;
	  break;
	}
    }

  if (strcmp (ps->flavour, "?") == 0)
    {
      const struct flavour_t *f;
      fprintf (stderr, "I know: ");
      for (f = flavours; f->name != 0; f++)
	fprintf (stderr, "%s ", f->name);
      fprintf(stderr, "\n");
    }
  else if (! f->name)
    {
      fprintf (stderr, "unknown profiling flavour `%s', S[?] to list\n", ps->flavour);
    }

  attr.size = sizeof(struct perf_event_attr);
  attr.sample_type = PERF_SAMPLE_IP;
  /* attr.read_format = PERF_FORMAT_GROUP | PERF_FORMAT_ID; */
  attr.disabled=1;
  attr.pinned=1;
  attr.exclude_kernel=1;
  attr.exclude_hv=1;

  attr.sample_period = ps->interval;
  /* attr.watermark=0; */
  /* attr.wakeup_events=1; */
  
  int fd = perf_event_open(&attr, 0, -1, -1, 0);
  if (fd == -1)
    {
      printf ("! perf_event_open %m\n");
    }

  ps->perf_event_fd = fd;

  fcntl(fd, F_SETFL, O_RDWR|O_NONBLOCK|O_ASYNC);
  fcntl(fd, F_SETSIG, SIGPROF);
  fcntl(fd, F_SETOWN, getpid());

  ioctl(fd, PERF_EVENT_IOC_RESET, 0);

  int err = ioctl(fd, PERF_EVENT_IOC_ENABLE, 0);
  if (err != 0)
    printf ("! perf_events enable\n");
}



/* Start profiling timer. */
static void profile_timer_start(ProfileState *ps)
{
  struct sigaction sa = {
    .sa_flags = SA_RESTART,
    .sa_handler = profile_signal
  };

  sigemptyset(&sa.sa_mask);
  sigaction(SIGPROF, &sa, &ps->oldsa);

  if (strcmp(ps->flavour, "vanilla") == 0)
    {
      int interval = ps->interval;
      struct itimerval tm;
      tm.it_value.tv_sec = tm.it_interval.tv_sec = interval / 1000;
      tm.it_value.tv_usec = tm.it_interval.tv_usec = (interval % 1000) * 1000;
      setitimer(ITIMER_PROF, &tm, NULL);
    }
  else
    {
      register_prof_events(ps);
    }
}



/* Stop profiling timer. */
static void profile_timer_stop(ProfileState *ps)
{
  if (ps->perf_event_fd)
    {
      ioctl(ps->perf_event_fd, PERF_EVENT_IOC_DISABLE, 0);
    }
  else
    {
      struct itimerval tm;
      tm.it_value.tv_sec = tm.it_interval.tv_sec = 0;
      tm.it_value.tv_usec = tm.it_interval.tv_usec = 0;
      setitimer(ITIMER_PROF, &tm, NULL);
      sigaction(SIGPROF, &ps->oldsa, NULL);
    }
}

#elif LJ_PROFILE_PTHREAD

/* POSIX timer thread. */
static void *profile_thread(ProfileState *ps)
{
  int interval = ps->interval;
#if !LJ_TARGET_PS3
  struct timespec ts;
  ts.tv_sec = interval / 1000;
  ts.tv_nsec = (interval % 1000) * 1000000;
#endif
  while (1) {
#if LJ_TARGET_PS3
    sys_timer_usleep(interval * 1000);
#else
    nanosleep(&ts, NULL);
#endif
    if (ps->abort) break;
    profile_trigger(ps);
  }
  return NULL;
}

/* Start profiling timer thread. */
static void profile_timer_start(ProfileState *ps)
{
  pthread_mutex_init(&ps->lock, 0);
  ps->abort = 0;
  pthread_create(&ps->thread, NULL, (void *(*)(void *))profile_thread, ps);
}

/* Stop profiling timer thread. */
static void profile_timer_stop(ProfileState *ps)
{
  ps->abort = 1;
  pthread_join(ps->thread, NULL);
  pthread_mutex_destroy(&ps->lock);
}

#elif LJ_PROFILE_WTHREAD

/* Windows timer thread. */
static DWORD WINAPI profile_thread(void *psx)
{
  ProfileState *ps = (ProfileState *)psx;
  int interval = ps->interval;
#if LJ_TARGET_WINDOWS
  ps->wmm_tbp(interval);
#endif
  while (1) {
    Sleep(interval);
    if (ps->abort) break;
    profile_trigger(ps);
  }
#if LJ_TARGET_WINDOWS
  ps->wmm_tep(interval);
#endif
  return 0;
}

/* Start profiling timer thread. */
static void profile_timer_start(ProfileState *ps)
{
#if LJ_TARGET_WINDOWS
  if (!ps->wmm) {  /* Load WinMM library on-demand. */
    ps->wmm = LoadLibraryExA("winmm.dll", NULL, 0);
    if (ps->wmm) {
      ps->wmm_tbp = (WMM_TPFUNC)GetProcAddress(ps->wmm, "timeBeginPeriod");
      ps->wmm_tep = (WMM_TPFUNC)GetProcAddress(ps->wmm, "timeEndPeriod");
      if (!ps->wmm_tbp || !ps->wmm_tep) {
	ps->wmm = NULL;
	return;
      }
    }
  }
#endif
  InitializeCriticalSection(&ps->lock);
  ps->abort = 0;
  ps->thread = CreateThread(NULL, 0, profile_thread, ps, 0, NULL);
}

/* Stop profiling timer thread. */
static void profile_timer_stop(ProfileState *ps)
{
  ps->abort = 1;
  WaitForSingleObject(ps->thread, INFINITE);
  DeleteCriticalSection(&ps->lock);
}

#endif

/* -- Public profiling API ------------------------------------------------ */

/* Start profiling. */
LUA_API void luaJIT_profile_start(lua_State *L, const char *mode,
				  luaJIT_profile_callback cb, void *data)
{
  ProfileState *ps = &profile_state;
  int interval = LJ_PROFILE_INTERVAL_DEFAULT;
  char *flavour;

  while (*mode) {
    int m = *mode++;
    switch (m) {
    case 'i':
      interval = 0;
      while (*mode >= '0' && *mode <= '9')
	interval = interval * 10 + (*mode++ - '0');
      if (interval <= 0) interval = 1;
      break;
#if LJ_HASJIT
    case 'l': case 'f':
      L2J(L)->prof_mode = m;
      lj_trace_flushall(L);
      break;
#endif
    case 'S':
      {
	int k;
	if (sscanf (mode, "[%m[^]]]%n", &flavour, &k) > 0)
	  mode += k;
      }

    default:  /* Ignore unknown mode chars. */
      break;
    }
  }
  if (ps->g) {
    luaJIT_profile_stop(L);
    if (ps->g) return;  /* Profiler in use by another VM. */
  }
  ps->g = G(L);
  ps->interval = interval;
  ps->cb = cb;
  ps->data = data;
  ps->samples = 0;
  ps->flavour = flavour;
  lj_buf_init(L, &ps->sb);
  profile_timer_start(ps);
}

/* Stop profiling. */
LUA_API void luaJIT_profile_stop(lua_State *L)
{
  ProfileState *ps = &profile_state;
  global_State *g = ps->g;
  if (G(L) == g) {  /* Only stop profiler if started by this VM. */
    profile_timer_stop(ps);
    g->hookmask &= ~HOOK_PROFILE;
    lj_dispatch_update(g);
#if LJ_HASJIT
    G2J(g)->prof_mode = 0;
    lj_trace_flushall(L);
#endif
    lj_buf_free(g, &ps->sb);
    setmref(ps->sb.b, NULL);
    setmref(ps->sb.e, NULL);
    ps->g = NULL;
  }
}

/* Return a compact stack dump. */
LUA_API const char *luaJIT_profile_dumpstack(lua_State *L, const char *fmt,
					     int depth, size_t *len)
{
  ProfileState *ps = &profile_state;
  SBuf *sb = &ps->sb;
  setsbufL(sb, L);
  lj_buf_reset(sb);
  lj_debug_dumpstack(L, sb, fmt, depth);
  *len = (size_t)sbuflen(sb);
  return sbufB(sb);
}

#endif
