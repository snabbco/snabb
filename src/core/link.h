enum { LINK_RING_SIZE    = 8192,
       LINK_MAX_PACKETS  = 8191
};

struct link {
  // this is a circular ring buffer, as described at:
  //   http://en.wikipedia.org/wiki/Circular_buffer
  // Two cursors:
  //   read:  the next element to be read
  //   write: the next element to be written
  int read, write;
  // Index (into the Lua app.active_apps array) of the app that
  // receives from this link.
  int receiving_app;
  // True when there are new packets to process.
  // Set when a new packet is added to the ring and cleared after
  // 'receiving_app' runs.
  bool has_new_data;
  struct packet* packets[LINK_RING_SIZE];
  struct {
    double txbytes, rxbytes, txpackets, rxpackets, txdrop;
  } stats;
};

