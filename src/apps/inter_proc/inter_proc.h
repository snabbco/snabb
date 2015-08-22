
struct link_t {
   struct packet *packets[LINK_RING_SIZE];
   struct packet *ret_pks[LINK_RING_SIZE];
   int write, read;
};
