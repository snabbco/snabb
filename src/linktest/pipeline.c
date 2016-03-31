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
pipeline_test(int n)
{
  assert(n >= 2);
  assert(n <= ncpus);

  int nthreads = n;
  int nlinks = n - 1;
  LINK **links;
  
  links = calloc(nlinks, sizeof(LINK *));
  for (int i = 0; i < nlinks; i++) {
    void *p;
    int error;

    error = posix_memalign(&p, CACHE_LINE_SIZE, sizeof(LINK));
    if (error) fatal("posix_memalign");
    links[i] = p;
    memset(links[i], 0, sizeof(LINK));
  }
  
  pthread_t generator_thread, discarder_thread;
  pthread_t *relay_threads;
  
  int nrelayers = nthreads - 2;
  
  if (nrelayers > 0) {
    relay_threads = calloc(nrelayers, sizeof(pthread_t));
  }

  struct thread_params *params;
  
  params = calloc(nthreads, sizeof(struct thread_params));
  
  pthread_attr_t attrs;
  cpu_set_t set;
  int error;
  pthread_attr_init(&attrs);
  
  CPU_ZERO(&set);
  CPU_SET(n - 1, &set);
  pthread_attr_setaffinity_np(&attrs, sizeof(set), &set);
  params[nthreads - 1].inputs[0] = links[nlinks - 1];
  params[nthreads - 1].ninputs = 1;
  if (debug) {
    printf("creating discarder thread, on cpu %d\n", n - 1);
  }
  error = pthread_create(&discarder_thread, &attrs, discard_single_input,
			 &params[nthreads - 1]);
  errchk(error, "discarder pthread_create");
  
  for (int i = 0, threadno = 1; i < nrelayers; i++, threadno++) {
    CPU_ZERO(&set);
    CPU_SET(threadno, &set);
    pthread_attr_setaffinity_np(&attrs, sizeof(set), &set);
    params[threadno].inputs[0] = links[threadno - 1];
    params[threadno].ninputs = 1;
    params[threadno].outputs[0] = links[threadno];
    params[threadno].noutputs = 1;
    if (debug) {
      printf("creating relayer thread, on cpu %d\n", threadno);
    }
    error = pthread_create(&relay_threads[i], &attrs, relay_simple,
			   &params[threadno]);
    errchk(error, "relayer pthread_create");
    pthread_detach(relay_threads[i]);
  }

  CPU_ZERO(&set);
  CPU_SET(0, &set);
  pthread_attr_setaffinity_np(&attrs, sizeof(set), &set);
  params[0].outputs[0] = links[0];
  params[0].noutputs = 1;
  params[0].delay = 0;
  if (debug) {
    printf("creating generator thread, on cpu %d\n", 0);
  }
  error = pthread_create(&generator_thread, &attrs, generate_single_output,
			 &params[0]);
  errchk(error, "generator pthread_create");
  pthread_detach(generator_thread);
  
  struct timeval start, end, elapsed;
  uintptr_t total_discarded;
  gettimeofday(&start, NULL);
  pthread_join(discarder_thread, (void **)&total_discarded);
  gettimeofday(&end, NULL);
  timersub(&end, &start, &elapsed);

  double seconds = elapsed.tv_sec + elapsed.tv_usec/1000000.0;
  printf("elapsed time for %" PRIu64 " elements: %f sec\n", total_discarded,
	 seconds);
  printf("dropped packets: %" PRIu64 " (%.1f%%)\n", total_dropped,
	 100*total_dropped/(double)total_packets);
  printf("%7.2f Mpps\n", total_discarded/seconds/1e6);
}
  
