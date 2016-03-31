#define LINK_RING_SIZE 256
#define NEXT(n) ((n + 1) & (LINK_RING_SIZE - 1))

/*
 * Classic lock-free ring buffer.
 */
struct basic_link {
  void *buffer[LINK_RING_SIZE];
  volatile int32_t read;
  volatile int32_t write;
};

static inline void *
basic_transmit(struct basic_link *link, void *datum)
{
  int32_t next = NEXT(link->write);
  if (next == link->read) {
    return NULL;
  } else {
    link->buffer[link->write] = datum;
    link->write = next;
    return datum;
  }
}

static inline void *
basic_receive(struct basic_link *link)
{
  if (link->read == link->write) {
    return NULL;
  } else {
    void *datum = link->buffer[link->read];
    link->read = NEXT(link->read);
    return datum;
  }
}
