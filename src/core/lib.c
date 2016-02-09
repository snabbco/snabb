#include <stdint.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

/* Return the current wall-clock time in nanoseconds. */
uint64_t get_time_ns()
{
    /* XXX Consider using RDTSC. */
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static double get_time(int clock)
{
  struct timespec ts;
  clock_gettime(clock, &ts);
  return ts.tv_sec + (ts.tv_nsec / 1000000000.0);
}

/* Return monotonic time (in seconds) suitable for timers. */
double get_monotonic_time()
{
  return get_time(CLOCK_MONOTONIC);
}

/* Return real wall-clock time in seconds since the epoch. */
double get_unix_time()
{
  return get_time(CLOCK_REALTIME);
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

/* Return last-modified-time for file or 0 on failure. */
unsigned int stat_mtime(const char *path)
{
  struct stat s;
  if (stat(path, &s) == 0) {
    return s.st_mtime;
  } else {
    return 0;
  }
}

