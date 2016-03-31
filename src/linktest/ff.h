#define LINK_RING_SIZE 256
#define NEXT(n) ((n + 1) & (LINK_RING_SIZE - 1))

/*
 * FastForward-style ring buffer. Note that read and write
 * fields are on their own cache lines.
 */
struct ff_link {
  void *buffer[LINK_RING_SIZE];
  volatile int32_t read __attribute__((aligned(CACHE_LINE_SIZE)));
  volatile int32_t write __attribute__((aligned(CACHE_LINE_SIZE)));
};

static inline void *
ff_transmit(struct ff_link *link, void *datum)
{
  if (link->buffer[link->write] != NULL) {
    return NULL;
  } else {
    link->buffer[link->write] = datum;
    link->write = NEXT(link->write);
    return datum;
  }
}

static inline void *
ff_receive(struct ff_link *link)
{
  void *datum = link->buffer[link->read];

  if (datum != NULL) {
    link->buffer[link->read] = NULL;
    link->read = NEXT(link->read);
  }
  return datum;
}
