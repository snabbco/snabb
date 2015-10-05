// Location where the next instruction pointer value will be stored.

#include <assert.h>
#include <stdio.h>
#define __USE_GNU
#include <stdint.h>
#include <stdlib.h>
#include <sys/time.h>
#include <signal.h>
#include <ucontext.h>

#include "traceprof.h"

static int samples;
static int logsize;
static uint64_t *log;

// Callback function to handle sigprof.
void traceprof_cb(int sig, siginfo_t *info, void *data)
{
  (void)sig;
  (void)data;
  if (samples < logsize) {
    uint64_t ip = (uint64_t)((ucontext_t*)data)->uc_mcontext.gregs[REG_RIP];
    log[samples] = ip;
  }
  samples++;
}

void traceprof_start(uint64_t *logptr, int maxsamples, int usecs)
{
  // Initialize state
  samples = 0;
  logsize = maxsamples;
  log = logptr;

  // Setup signal handler
  struct sigaction sa = {
    .sa_flags = SA_RESTART|SA_SIGINFO,
    .sa_sigaction = traceprof_cb
  };
  sigemptyset(&sa.sa_mask);
  sigaction(SIGPROF, &sa, NULL);

  // Start interal timer (signal source)
  struct itimerval tm;
  tm.it_value.tv_sec  = tm.it_interval.tv_sec  = usecs/1000000;
  tm.it_value.tv_usec = tm.it_interval.tv_usec = usecs%1000000;
  setitimer(ITIMER_PROF, &tm, NULL);
}

int traceprof_stop()
{
  struct itimerval tm;
  tm.it_value.tv_sec = tm.it_interval.tv_sec = 0;
  tm.it_value.tv_usec = tm.it_interval.tv_usec = 0;
  setitimer(ITIMER_PROF, &tm, NULL);
  sigaction(SIGPROF, NULL, NULL);
  return samples;
}

