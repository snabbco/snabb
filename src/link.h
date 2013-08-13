enum { LINK_MAX_PACKETS = 10000 };

struct link {
  int head, tail;
  struct packet* packets[LINK_MAX_PACKETS];
  struct {
    uint64_t tx, rx, drop;
  } stats;
};

