/* Use of this source code is governed by the Apache 2.0 license; see COPYING. */

enum { LINK_RING_SIZE    = 1024,
       LINK_MAX_PACKETS  = LINK_RING_SIZE - 1
};

struct link {
  // this is a circular ring buffer, as described at:
  //   http://en.wikipedia.org/wiki/Circular_buffer
  struct packet *packets[LINK_RING_SIZE];
  struct {
    struct counter *dtime, *txbytes, *rxbytes, *txpackets, *rxpackets, *txdrop;
  } stats;
  // Two cursors:
  //   read:  the next element to be read
  //   write: the next element to be written
  int read, write;
};

