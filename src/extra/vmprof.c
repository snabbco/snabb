/*
** VM profiler.
** Copyright (C) 2005-2011 Mike Pall. See Copyright Notice in luajit.h
*/

#include <stdio.h>

#define LUA_LIB

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include "lj_obj.h"

/* Extra states for use in profiler only. */
#define LJ_VMST_MCODE	LJ_VMST__MAX
#define LJ_VMST_PMAX	(LJ_VMST__MAX+1)

#define LJ_VMST_STARTUP	(LJ_VMST__MAX+1)
#define LJ_VMST_FINISH	(LJ_VMST__MAX+2)

/* Default settings. Override with -j vmprof[=blen[,rate[,file]]]. */
#define LJ_VMPROF_BLEN	0		/* Sample buffer length in seconds. */
#define LJ_VMPROF_RATE	100		/* Sampling rate in microseconds. */
#define LJ_VMPROF_FILE	"vmprof.?.gif"	/* File name. '?' -> pid. */

typedef struct VMProfCtx {
  /* Results. */
  int32_t samples;		/* Sample counter. */
  int32_t states[LJ_VMST_PMAX];	/* Per-state sample counters. */
  int32_t duration;		/* Total sampling duration in milliseconds. */
  int32_t pid;			/* Process ID. */
  /* Settings. */
  int32_t *vmst;		/* Pointer to g->vmstate. */
  int32_t bufsz;		/* Sample buffer size in bytes. */
  uint8_t *buf;			/* Sample buffer. */
  int rate;			/* Sampling rate in microseconds. */
  int blen;			/* Sample buffer length in seconds. */
} VMProfCtx;

/* -- Sampling function --------------------------------------------------- */

/* Add a new sample to the sampling buffer and update the counters. */
static void sample_add(VMProfCtx *vmp, int32_t st)
{
  int32_t idx;
  int32_t bst;
  if (st >= 0) {
    vmp->states[LJ_VMST_MCODE]++;
    bst = 1+LJ_VMST_MCODE + (st & 7); //XXX
  } else {
    vmp->states[~st]++;
    bst = -st;
  }
  idx = vmp->samples++;
  if (vmp->blen < 0) {
    ((int32_t *)vmp->buf)[(LJ_VMST__MAX+st)&4095]++;
  } else {
    if (idx < vmp->bufsz)
      vmp->buf[idx] = bst;
  }
}

/* -- Platform specifics -------------------------------------------------- */

#if LJ_TARGET_WINDOWS

#error "NYI: Windows port"

#elif LJ_TARGET_POSIX

#include <sys/types.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <time.h>


#if LJ_TARGET_LINUX
extern int sched_setaffinity(pid_t pid, size_t sz, const unsigned long *set);
static void sample_setaffinity(unsigned long af)
{
  sched_setaffinity(0, sizeof(unsigned long), &af);
}
#else
#define sample_setaffinity(af)	((void)(af))
#endif

static pthread_t sample_thr;

/* Sampling thread main function. */
static void *sample_main(void *addr)
{
  VMProfCtx *vmp = (VMProfCtx *)addr;
  volatile int32_t *vmst = vmp->vmst;
  struct timespec t1, t2, delta;
  int st;
  sample_setaffinity(2UL);  /* Run sampling thread only on the 2nd CPU. */
  delta.tv_sec = vmp->rate / 1000000;
  delta.tv_nsec = (vmp->rate % 1000000) * 1000;
  while ((st = *vmst) == ~LJ_VMST_STARTUP)
    sched_yield();
  clock_gettime(CLOCK_MONOTONIC, &t1);
  t2 = t1;
  while (st != ~LJ_VMST_FINISH) {
    sample_add(vmp, st);
    t2.tv_nsec += delta.tv_nsec;
    t2.tv_sec += delta.tv_sec;
    if (t2.tv_nsec >= 1000000000) { t2.tv_nsec -= 1000000000; t2.tv_sec++; }
    clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &t2, NULL);
    st = *vmst;
  }
  clock_gettime(CLOCK_MONOTONIC, &t2);
  vmp->duration = (t2.tv_sec - t1.tv_sec) * 1000 +
		  (t2.tv_nsec - t1.tv_nsec + 500000) / 1000000;
  return NULL;
}

/* Start sampling thread. */
static int sample_start(VMProfCtx *vmp)
{
  pthread_attr_t attr;
  if (vmp->blen) {
    if (vmp->blen < 0)
      vmp->bufsz = 4*4096;
    else
      vmp->bufsz = (((int64_t)vmp->blen*1000000)/vmp->rate + 4095) & ~4095;
    vmp->buf = (uint8_t *)mmap(NULL, (size_t)vmp->bufsz, PROT_READ|PROT_WRITE,
			       MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if ((void *)vmp->buf == MAP_FAILED)
      return 1;
    vmp->pid = (int32_t)getpid();
  }
  *vmp->vmst = ~LJ_VMST_STARTUP;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, 1<<17);  /* Reduce default stack size. */
  pthread_create(&sample_thr, &attr, sample_main, (void *)vmp);
  sample_setaffinity(~2UL);  /* Don't run app thread on the 2nd CPU. */
  sched_yield();
  *vmp->vmst = ~LJ_VMST_C;
  return 0;
}

/* Stop sampling thread. */
static void sample_stop(VMProfCtx *vmp)
{
  *vmp->vmst = ~LJ_VMST_FINISH;
  pthread_join(sample_thr, NULL);
  *vmp->vmst = ~LJ_VMST_C;
}

/* Free sampling buffer. */
static void sample_free(VMProfCtx *vmp)
{
  if (vmp->bufsz)
    munmap(vmp->buf, vmp->bufsz);
}

#else
#error "VM profiler not supported on this platform (Windows or POSIX only)"
#endif

/* -- Profile output ------------------------------------------------------ */

static uint8_t vmprof_cmap[] = {
  0x00, 0x00, 0x00,	/* Background:		black (transparent) */
  0x80, 0x80, 0x80,	/* Interpreter:		grey */
  0x00, 0x00, 0xff,	/* C function:		blue */
  0x00, 0xc0, 0xc0,	/* Garbage collector:	cyan */
  0xff, 0xff, 0x00,	/* Trace exit handler:	yellow */
  0xff, 0x00, 0xff,	/* Trace recorder:	magenta */
  0xff, 0x60, 0x00,	/* Optimizer:		orange */
  0xff, 0x00, 0x00,	/* Assembler:		red */
  0x00, 0xff, 0x00,	/* Machine code + (traceno & 7): shades of green */
  0x00, 0xe7, 0x00,
  0x00, 0xcf, 0x00,
  0x00, 0xb7, 0x00,
  0x00, 0x9f, 0x00,
  0x00, 0x87, 0x00,
  0x00, 0x6f, 0x00,
  0x00, 0x57, 0x00
};
#define VMPROF_CMAP_TRANSP	0
#define VMPROF_CMAP_BITS	4

#define VMPROF_HEIGHT		256
#define VMPROF_HEIGHT2		(VMPROF_HEIGHT+3+3)

/* Buffer writer. Deliberately ignores errors and avoids compiler warnings. */
static void bufwrite(FILE *fp, uint8_t *buf, int32_t len)
{
  if (fwrite(buf, 1, (size_t)len, fp) != (size_t)len) {}
}

/* Dump VM profiler samples to an uncompressed GIF file. */
static void vmprof_dump(VMProfCtx *vmp, const char *fname)
{
  FILE *fp;
  uint8_t buf[128];
  uint8_t *p = vmp->buf;
  int32_t len = vmp->samples < vmp->bufsz ? vmp->samples : vmp->bufsz;
  int32_t w, wh, n, m, st;
  int32_t stsum[LJ_VMST_PMAX];
  w = (len + VMPROF_HEIGHT-1) / VMPROF_HEIGHT;
  wh = w * VMPROF_HEIGHT;
  /* Open file and write GIF89a header fields. */
  if (!(fp = fopen(fname, "wb"))) return;
  buf[0] = 'G'; buf[1] = 'I'; buf[2] = 'F';
  buf[3] = '8'; buf[4] = '9'; buf[5] = 'a';
  buf[6] = (uint8_t)w; buf[7] = (uint8_t)(w >> 8);
  buf[8] = (uint8_t)VMPROF_HEIGHT2; buf[9] = (uint8_t)(VMPROF_HEIGHT2 >> 8);
  buf[10] = 0xef + VMPROF_CMAP_BITS; buf[11] = 0; buf[12] = 0;
  bufwrite(fp, buf, 13);
  bufwrite(fp, vmprof_cmap, sizeof(vmprof_cmap));
  buf[10] = '!'; buf[11] = 0xf9; buf[12] = 4; buf[13] = 1;
  buf[14] = 0; buf[15] = 0; buf[16] = VMPROF_CMAP_TRANSP; buf[17] = 0;
  bufwrite(fp, buf+10, 8);
  buf[1] = ','; buf[2] = 0; buf[3] = 0; buf[4] = 0; buf[5] = 0;
  buf[10] = VMPROF_CMAP_BITS-1; buf[11] = 7;
  bufwrite(fp, buf+1, 11);
  buf[0] = 127; buf[1] = 128; n = 2;
  /* Write rotated image of sample buffer. */
  for (m = 0; ; m += VMPROF_HEIGHT) {
    if (m >= wh) {
      m = m - wh + 1;
      if (m >= VMPROF_HEIGHT) break;
    }
    buf[n++] = m < len ? p[m] : 0;
    if (n == 128) { bufwrite(fp, buf, 128); n = 2; }
  }
  /* Write 3 background lines. */
  for (m = 0; m < 3*w; m++) {
    buf[n++] = 0;
    if (n == 128) { bufwrite(fp, buf, 128); n = 2; }
  }
  /* Build cumulative sums of state samples. */
  stsum[0] = vmp->states[0];
  for (st = 1; st < LJ_VMST_PMAX; st++)
    stsum[st] = stsum[st-1] + vmp->states[st];
  /* Write 3 lines for state scale. */
  for (m = 0; m < 3; m++) {
    int32_t c, x;
    for (st = x = c = 0; x < w; x++) {
      while (c <= x) c = ((int64_t)w*stsum[st++]+(w>>1))/vmp->samples;
      buf[n++] = st;
      if (n == 128) { bufwrite(fp, buf, 128); n = 2; }
    }
  }
  /* Flush buffer and write footer. */
  if (n > 2) { buf[0] = n - 1; bufwrite(fp, buf, n); }
  buf[0] = 1; buf[1] = 129; buf[2] = 0; buf[3] = ';';
  bufwrite(fp, buf, 4);
  fclose(fp);
}

/* Print VM profiler summary. */
static void vmprof_summary(VMProfCtx *vmp)
{
  double pr[LJ_VMST_PMAX];
  double samples = (double)vmp->samples;
  char buf[80];
  int i;
  if (vmp->samples == 0) return;
  for (i = 0; i < LJ_VMST_PMAX; i++)
    pr[i] = vmp->states[i]*100.0/samples;
  sprintf(buf,
    "[VMProf: %5.3fs %5.1fM %5.1fI %5.1fC%5.1fG  %5.1fX%5.1fR%5.1fO%5.1fA]\n",
    ((double)vmp->duration)/1000.0,
    pr[LJ_VMST_MCODE],
    pr[LJ_VMST_INTERP],
    pr[LJ_VMST_C],
    pr[LJ_VMST_GC],
    pr[LJ_VMST_EXIT],
    pr[LJ_VMST_RECORD],
    pr[LJ_VMST_OPT],
    pr[LJ_VMST_ASM]);
  for (i = 17; buf[i]; i++)
    if (buf[i] == ' ' && buf[i+1] == '0' && buf[i+2] == '.' && buf[i+3] == '0')
      buf[i+1] = buf[i+2] = buf[i+3] = ' ';
  fputs(buf, stderr);
}

static void vmprof_list(VMProfCtx *vmp)
{
  int i;
  int32_t *counts = (int32_t *)vmp->buf;
  double isamp = 100.0/(double)vmp->samples;
  for (i = 0; i < LJ_VMST__MAX; i++)
    if (counts[i])
      printf("#%c %5.1f\n", "AORXGCI"[i], (double)counts[i]*isamp);
  for (i = 0; i < 4096-LJ_VMST__MAX; i++)
    if (counts[LJ_VMST__MAX+i])
      printf("%-2d %5.1f\n", i, (double)counts[LJ_VMST__MAX+i]*isamp);
}

/* -- Library functions --------------------------------------------------- */

static int vmprof_gc(lua_State *L)
{
  VMProfCtx *vmp = (VMProfCtx *)lua_touserdata(L, 1);
  sample_stop(vmp);
  if (vmp->blen > 0) {
    lua_getmetatable(L, 1);
    lua_getfield(L, -1, "file");
    lua_pushinteger(L, (lua_Integer)vmp->pid);
    vmprof_dump(vmp,
		luaL_gsub(L, lua_tostring(L, -2), "?", lua_tostring(L, -1)));
    lua_pop(L, 4);
  }
  vmprof_summary(vmp);
  if (vmp->blen < 0)
    vmprof_list(vmp);
  sample_free(vmp);
  return 0;
}

/* JIT command for VM profiler: -j vmprof[=blen[,rate[,file]]]. */
static int vmprof_start(lua_State *L)
{
  VMProfCtx *vmp;
  lua_settop(L, 3);  /* Fix args below userdata for type checks. */
  vmp = (VMProfCtx *)lua_newuserdata(L, sizeof(VMProfCtx));
  memset(vmp, 0, sizeof(VMProfCtx));
  vmp->vmst = (int32_t *)&G(L)->vmstate;
  vmp->blen = luaL_optint(L, 1, LJ_VMPROF_BLEN);
  vmp->rate = luaL_optint(L, 2, LJ_VMPROF_RATE);
  if (vmp->rate <= 0) vmp->rate = 1;
  lua_createtable(L, 0, 2);
  lua_pushcfunction(L, vmprof_gc);
  lua_setfield(L, -2, "__gc");
  lua_pushstring(L, luaL_optstring(L, 3, LJ_VMPROF_FILE));
  lua_setfield(L, -2, "file");
  lua_setmetatable(L, -2);
  lua_setfield(L, LUA_REGISTRYINDEX, "VMProfCtx");
  if (sample_start(vmp))
    luaL_error(L, "cannot allocate sample buffer");
  return 0;
}

static int vmprof_tstart(lua_State *L)
{
  VMProfCtx *vmp;
  int32_t rate = luaL_optint(L, 1, LJ_VMPROF_RATE);
  if (rate <= 0) rate = 1;
  vmp = (VMProfCtx *)lua_newuserdata(L, sizeof(VMProfCtx));
  memset(vmp, 0, sizeof(VMProfCtx));
  vmp->vmst = (int32_t *)&G(L)->vmstate;
  vmp->blen = -1;
  vmp->rate = rate;
  if (sample_start(vmp))
    luaL_error(L, "cannot allocate sample buffer");
  return 1;
}

static int vmprof_tstop(lua_State *L)
{
  VMProfCtx *vmp = (VMProfCtx *)lua_touserdata(L, 1);
  sample_stop(vmp);
  lua_pushinteger(L, vmp->samples);
  return 1;
}

static int vmprof_tcount(lua_State *L)
{
  VMProfCtx *vmp = (VMProfCtx *)lua_touserdata(L, 1);
  int32_t idx = (luaL_checkint(L, 2) + LJ_VMST__MAX) & 4095;
  lua_pushinteger(L, ((int32_t *)vmp->buf)[idx]);
  return 1;
}

/* VM profiler library functions. */
static const luaL_Reg vmproflib[] = {
  { "start",	vmprof_start },
  { "tstart",	vmprof_tstart },
  { "tstop",	vmprof_tstop },
  { "tcount",	vmprof_tcount },
  { NULL, NULL }
};

/* Open VM profiler library. */
LUALIB_API int luaopen_jit_vmprof(lua_State *L)
{
  luaL_register(L, "jit.vmprof", vmproflib);
  return 1;
}

