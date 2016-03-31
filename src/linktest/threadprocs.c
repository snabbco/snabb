#include <inttypes.h>
#include <pthread.h>
#include <sys/time.h>
#include <assert.h>

#include "linktest.h"

/*
 * Receive values from a single input, and re-send them to a single output.
 */
void *
relay_simple(void *arg)
{
  struct thread_params *params = arg;

  assert(params->ninputs == 1);
  assert(params->noutputs == 1);

  LINK *input = params->inputs[0];
  LINK *output = params->outputs[0];
  void *datum;

  while (runflag) {
    datum = RECEIVE(input);
    if (params->delay) rdtsc_spin(params->delay);
    if (datum) {
      void *sent = NULL;
      while (sent == NULL && runflag) {
	sent = TRANSMIT(output, datum);
      }
    }
  }
  /*
   * It's possible that there will still be some data in the input
   * link.  We could try to relay it here, but by the  time we finish,
   * the consumer thread on the output link will probably already be
   * gone.
   */
  return NULL;
}

/*
 * Receive and discard values from a single input link.
 */
void *
discard_single_input(void *arg)
{
  struct thread_params *params = arg;
  uintptr_t discarded = 0;

  assert(params->ninputs == 1);

  LINK *input = params->inputs[0];
  void *datum;

  while (runflag) {
    datum = RECEIVE(input);
    if (datum) {
      if (params->delay) rdtsc_spin(params->delay);
      discarded++;
    }
  }
  /* drain anything left in the input link */
  while ((datum = RECEIVE(input)) != NULL) {
    discarded++;
  }
  pthread_exit((void *)discarded);
  return NULL;
}

/*
 * Receive and discard values from all input links.
 */
void *
discard_inputs(void *arg)
{
  struct thread_params *params = arg;
  uintptr_t discarded = 0;

  assert(params->ninputs > 0);

  while (runflag) {
    for (int i = 0; i < params->ninputs; i++) {
      void *datum = RECEIVE(params->inputs[i]);
      if (datum) {
	if (params->delay) rdtsc_spin(params->delay);
	discarded++;
      }
    }
  }
  pthread_exit((void *)discarded);
  return NULL;
}

/*
 * Generate a value and send it to the single output link.
 */
void *
generate_single_output(void *arg)
{
  struct thread_params *params = arg;

  assert(params->ninputs == 0);
  assert(params->noutputs == 1);

  uint64_t n = 0;
  void *datum;

  for (int i = 0; i < total_packets; i++) {
    if (params->delay) rdtsc_spin(params->delay);
    datum = TRANSMIT(params->outputs[0], (void *)++n);
    if (datum == NULL) total_dropped++;
  }
  runflag = 0;
  return NULL;
}

/*
 * Generate a value and send it to all of the output links.
 */
void *
generate_broadcast(void *arg)
{
  struct thread_params *params = arg;

  assert(params->ninputs == 0);
  assert(params->noutputs > 0);

  uint64_t n = 0;

  for (int i = 0; i < total_packets; i++) {
    if (params->delay) rdtsc_spin(params->delay);
    n = n + 1;
    for (int j = 0; j < params->noutputs; j++) {
      TRANSMIT(params->outputs[0], (void *)n);
    }
  }
  runflag = 0;
  return NULL;
}

/*
 * Generate a value and send it to one of the outputs, which is
 * selected in round-robin fashion.
 */
void *
generate_round_robin(void *arg)
{
  struct thread_params *params = arg;

  assert(params->ninputs == 0);
  assert(params->noutputs > 0);

  uint64_t n = 0;
  void *datum;
  int dest = 0;

  for (int i = 0; i < total_packets; i++) {
    if (params->delay) rdtsc_spin(params->delay);
    n = n + 1;
    datum = TRANSMIT(params->outputs[dest], (void *)n);
    if (datum == NULL) total_dropped++;
    dest = dest + 1;
    if (dest == params->noutputs) dest = 0;
  }
  runflag = 0;
  return NULL;
}
