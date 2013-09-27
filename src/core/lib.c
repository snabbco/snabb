#include <stdint.h>
#include <time.h>
#include <sys/time.h>

/* Return the current wall-clock time in nanoseconds. */
uint64_t get_time_ns()
{
    /* XXX Consider using RDTSC. */
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

/* Sleep for a given number of nanoseconds.
   Must be less than 1 second. */
void sleep_ns(int nanoseconds)
{
  static struct timespec time;
  struct timespec rem;
  time.tv_nsec = nanoseconds;
  nanosleep(&time, &rem);
}

/* Execute a full CPU hardware memory barrier.
   See: http://en.wikipedia.org/wiki/Memory_barrier */
void full_memory_barrier()
{
  // See http://gcc.gnu.org/onlinedocs/gcc-4.1.1/gcc/Atomic-Builtins.html
  __sync_synchronize();
}

/* Prefetch memory at address into CPU cache. */
void prefetch_for_read(const void *address)
{
  __builtin_prefetch(address, 0);
}

/* Prefetch memory at address into CPU cache. */
void prefetch_for_write(const void *address)
{
  __builtin_prefetch(address, 1);
}

