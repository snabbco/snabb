/* Use of this source code is governed by the Apache 2.0 license; see COPYING. */

enum { LINK_RING_SIZE    = 1024,
       LINK_MAX_PACKETS  = LINK_RING_SIZE - 1,
       CACHE_LINE        = 64
};

struct link {
  // this is a circular ring buffer, as described at:
  //   http://en.wikipedia.org/wiki/Circular_buffer
  char pad0[CACHE_LINE];
  // Two cursors:
  //   read:  the next element to be read
  //   write: the next element to be written
  int read, write;
  struct counter dtime;
  char pad1[CACHE_LINE-2*sizeof(int)-sizeof(struct counter)];
  // consumer-local cursors
  int lwrite, nread;
  struct counter rxbytes, rxpackets;
  char pad2[CACHE_LINE-2*sizeof(int)-2*sizeof(struct counter)];
  // producer-local cursors
  int lread, nwrite;
  struct counter txbytes, txpackets, txdrop;
  char pad3[CACHE_LINE-2*sizeof(int)-3*sizeof(struct counter)];
  struct packet *packets[LINK_RING_SIZE];
};

