#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>

#include "linktest.h"

int debug = 0;

int ncpus;
volatile int runflag;
uint64_t total_packets;
uint64_t total_discarded;
uint64_t total_dropped;
long work_nanoseconds;

static struct option longopts[] = {
  { "mode", required_argument, NULL, 'm' },
  { "threads", required_argument, NULL, 't' },
  { "packets", required_argument, NULL, 'p' },
  { "debug", no_argument, NULL, 'd' },
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
  int mode;

  ncpus = sysconf(_SC_NPROCESSORS_ONLN);
  runflag = 1;
  total_packets = (uint64_t)100e6;
  total_discarded = 0;
  total_dropped = 0;

  /* defaults */
  mode = PIPELINE_TEST;
  nthreads = 2;

  while ((ch = getopt_long(argc, argv, "m:p:t:", longopts, NULL)) != -1) {
    switch (ch) {
    case 'd':
      debug = 1;
      break;
    case 'm':
      if (strcmp(optarg, "pipeline") == 0) {
	mode = PIPELINE_TEST;
      } else if (strcmp(optarg, "fan") == 0) {
	mode = FAN_TEST;
      } else {
	usage(argv);
      }
      break;
    case 'p':
      total_packets = strtol(optarg, NULL, 10);
      if (total_packets < 1) {
	printf("the argument to -p/--packets must be an integer > 0\n");
	usage(argv);
      }
      break;
    case 't':
      nthreads = strtol(optarg, NULL, 10);
      if (nthreads < 2) {
	printf("the argument to -t/--threads must be a number >= 2\n");
	usage(argv);
      }
      break;
    default:
      usage(argv);
      break;
    }
  }

  if (mode == FAN_TEST && nthreads < 3) {
    fatal("the fan test needs at least 3 threads\n");
  }

  if (nthreads > ncpus) {
    fatal("can't have more threads (%d) than cpus (%d)\n", nthreads, ncpus);
    exit(1);
  }

  printf("link type: %s\n", LINKTYPE);
  printf("sending %" PRIu64 " packets\n", total_packets);
  if (mode == PIPELINE_TEST) {
    printf("pipeline test with %d stages\n", nthreads);
    pipeline_test(nthreads);
  } else if (mode == FAN_TEST) {
    printf("fanout test with generator and %d outputs\n", nthreads - 1);
    fan_test(nthreads);
  }
}
