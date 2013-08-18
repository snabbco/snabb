enum { LINK_RING_SIZE         = 10001,
       LINK_RING_MAX_PACKETS  = 10000
};

struct link {
  // link is a circular ring buffer, as described at:
  //   http://en.wikipedia.org/wiki/Circular_buffer
  int head, tail;
  struct packet* packets[LINK_RING_SIZE];
  struct {
    uint64_t tx, rx, drop;
  } stats;
};

