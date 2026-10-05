/* Use of this source code is governed by the Apache 2.0 license; see COPYING. */

uint64_t get_time_ns();
double get_monotonic_time();
double get_unix_time();
void sleep_ns(int nanoseconds);
void full_memory_barrier();
void prefetch_for_read(const void *address);
void prefetch_for_write(const void *address);
unsigned int stat_mtime(const char *path);
