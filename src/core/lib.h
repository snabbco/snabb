uint64_t get_time_ns();
void sleep_ns(int nanoseconds);
void full_memory_barrier();
void prefetch_for_read(const void *address);
void prefetch_for_write(const void *address);
