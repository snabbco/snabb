#include <inttypes.h>
#include <pthread.h>
#include <sys/time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/signal.h>
#include <sched.h>
#include <assert.h>

#include "linktest.h"

void
fan_test(int n)
{
  assert(n >= 3);
  assert(n <= ncpus);
  
  int nthreads = n;
  int nlinks = n - 1;
  LINK **links;
  
  links = calloc(nlinks, sizeof(LINK *));
  for (int i = 0; i < nlinks; i++) {
    int error;

    error = posix_memalign((void **)&links[i], CACHE_LINE_SIZE, sizeof(LINK));
    if (error) fatal("posix_memalign");
    memset(links[i], 0, sizeof(LINK));
  }

  pthread_t generator_thread;
  pthread_t *discarder_threads;
  int ndiscarders = nthreads - 1;
  struct thread_params *params;

  discarder_threads = calloc(ndiscarders, sizeof(pthread_t));
  params = calloc(nthreads, sizeof(struct thread_params));

  pthread_attr_t attrs;
  cpu_set_t set;
  int error;

  pthread_attr_init(&attrs);

  /* generator thread */
  CPU_ZERO(&set);
  CPU_SET(0, &set);
  pthread_attr_setaffinity_np(&attrs, sizeof(set), &set);
  for (int i = 0; i < nlinks; i++) {
    params[0].outputs[i] = links[i];
  }
  params[0].noutputs = nlinks;
  error = pthread_create(&generator_thread, &attrs, generate_round_robin,
			 &params[0]);
  errchk(error, "generator pthread_create");
  pthread_detach(generator_thread);

  for (int i = 0, threadno = 1; i < ndiscarders; i++, threadno++) {
    CPU_ZERO(&set);
    CPU_SET(threadno, &set);
    pthread_attr_setaffinity_np(&attrs, sizeof(set), &set);
    params[threadno].inputs[0] = links[i];
    params[threadno].ninputs = 1;
    error = pthread_create(&discarder_threads[i], &attrs, discard_single_input,
			   &params[threadno]);
    errchk(error, "discarder pthread_create");
  }

  struct timeval start, end, elapsed;
  uintptr_t x;
  uint64_t total_discarded = 0;
  gettimeofday(&start, NULL);
  for (int i = 0; i < ndiscarders; i++) {
    pthread_join(discarder_threads[i], (void **)&x);
    total_discarded += x;
  }
  gettimeofday(&end, NULL);
  timersub(&end, &start, &elapsed);

  double seconds = elapsed.tv_sec + elapsed.tv_usec/1000000.0;
  printf("elapsed time for %" PRIu64 " elements: %f sec\n", total_discarded,
	 seconds);
  printf("dropped packets: %" PRIu64 " (%.1f%%)\n", total_dropped,
	 (double)total_dropped/(double)total_packets);
  printf("%7.2f Mpps\n", total_discarded/seconds/1e6);
}


			   

