#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <getopt.h>

#include "linktest.h"

int ncpus;
int runflag;
uint64_t total_packets;
uint64_t total_discarded;
uint64_t total_dropped;
long work_nanoseconds;

static struct option longopts[] = {
  { "mode", required_argument, NULL, 'm' },
  { "threads", required_argument, NULL, 't' },
  { NULL, 0, NULL, 0}
};

void
usage(char *argv[])
{
  printf("usage: %s [options]\n", argv[0]);
  printf(" -m, --mode: test to run: one of \"pipeline\", \"fan\".\n");
  printf(" -t, --threads <n>: Use <n> threads. Must be <= number of cpus.\n");
  exit(1);
}

int
main(int argc, char *argv[])
{
  int ch;
  int nthreads;
  int test;

  ncpus = sysconf(_SC_NPROCESSORS_ONLN);
  runflag = 1;
  total_packets = (uint64_t)100e6;
  total_discarded = 0;
  total_dropped = 0;

  /* defaults */
  test = PIPELINE_TEST;
  nthreads = 2;

  while ((ch = getopt_long(argc, argv, "m:t:", longopts, NULL)) != -1) {
    switch (ch) {
    case 'm':
      break;
    case 't':
      break;
    default:
      usage(argv);
      break;
    }
  }

  if (nthreads > ncpus) {
    fatal("can't have more threads (%d) than cpus (%d)\n", nthreads, ncpus);
    exit(1);
  }

  printf("link type: %s\n", LINKTYPE);
  if (test == PIPELINE_TEST) {
    printf("pipeline test with %d stages\n", nthreads);
    pipeline_test(nthreads);
  } else if (test == FAN_TEST) {
    printf("fanout test with generator and %d outputs\n", nthreads - 1);
    fan_test(nthreads);
  }
}
