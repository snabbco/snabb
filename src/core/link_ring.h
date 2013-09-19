enum { LINK_RING_SIZE         = 10001,
       LINK_RING_MAX_PACKETS  = 10000
};

struct link_ring {
  // this is a circular ring buffer, as described at:
  //   http://en.wikipedia.org/wiki/Circular_buffer
  // Three cursors:
  //   write: the next element to be written
  //   read: the next element to be read
  //   deref: the next element to be deref'd
  int write, read, deref;
  struct packet* packets[LINK_RING_SIZE];
  struct {
    uint64_t tx, rx, drop;
  } stats;
};

