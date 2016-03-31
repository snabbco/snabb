#ifndef LINKTEST_H
#define LINKTEST_H

#define CACHE_LINE_SIZE 64

#if defined(BASIC_LINK) && !defined(FF_LINK)
#include "basic.h"
#define LINK struct basic_link
#define TRANSMIT(l, d) basic_transmit(l, d)
#define RECEIVE(l) basic_receive(l)
#define LINKTYPE "basic"
#elif defined(FF_LINK) && !defined(BASIC_LINK)
#include "ff.h"
#define LINK struct ff_link
#define TRANSMIT(l, d) ff_transmit(l, d)
#define RECEIVE(l) ff_receive(l)
#define LINKTYPE "ff"
#else
#error "Must define one of BASIC_LINK or FF_LINK"
#endif

#define MAX_INPUT_LINKS 16
#define MAX_OUTPUT_LINKS 16

struct thread_params {
  LINK *inputs[MAX_INPUT_LINKS];
  uint32_t ninputs;
  LINK *outputs[MAX_OUTPUT_LINKS];
  uint32_t noutputs;
  long delay;			/* in nanoseconds */
};

extern void errchk(int, char *);
extern void fatal(char *fmt, ...) __attribute__ ((noreturn));

extern int debug;

extern int ncpus;
extern int runflag;
extern uint64_t total_packets;
extern uint64_t total_dropped;
extern long work_nanoseconds;

/* start routines suitable for use in pthread_create() */
extern void *relay_simple(void *);
extern void *discard_single_input(void *);
extern void *discard_inputs(void *);
extern void *generate_single_output(void *);
extern void *generate_broadcast(void *);
extern void *generate_round_robin(void *);

enum {
  PIPELINE_TEST = 1,
  FAN_TEST = 2
};

extern void pipeline_test(int);
extern void fan_test(int);

#include <inttypes.h>
#include <x86intrin.h>

#define compiler_barrier() __asm__ __volatile__("" ::: "memory")

static inline void
rdtsc_spin(uint64_t ticks)
{
  uint64_t deadline = __rdtsc() + ticks;

  while (__rdtsc() < deadline) {
    compiler_barrier();
  }
}

#endif
