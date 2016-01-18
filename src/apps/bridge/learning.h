/* Type for port and split-horizon group handles */
typedef uint16_t handle_t;

/* List of egress port handles.  This fixed-sized declaration is used
   in mac_table.c.  The actual port lists are of variable size and
   allocated by learning.lua. */
typedef struct {
  uint16_t length;
  handle_t ports[1];
} port_list_t;

/* Packets are queued in various packet forwarding tables during
   processing in learning:push().  Each entry points to a list of port
   handles to which the packet will be sent. */
typedef struct {
  struct packet *p;
  port_list_t *plist;
} pft_entry_t;

typedef struct pft {
  uint16_t length;
  pft_entry_t entries[1];
} pft_t;

/* Mapping of a destination MAC address to an egress port handle.  The
   split-horizon group to which it belongs is stored as well in order
   to detect group collision during lookup.  The address is stored as
   a 64-bit integer in host-byte order to allow efficient access and
   comparison.  A bucket in the hash table is made up of an array of
   BUCKET_SIZE entries of this type. */
typedef struct {
  uint64_t mac;
  handle_t port;
  handle_t group;
} mac_entry_t;

/* The MAC addresses are stored in simple hash tables with fixed-sized
   buckets. */
typedef struct {
  uint32_t ubuckets; /* Number of buckets with at least one used slot */
  uint32_t entries;  /* Number of stored objects */
  uint8_t  overflow; /* Flag to indicate overflow in at least one bucket */
} hash_table_header_t;

/* This fixed-sized declaration is used in mac_table.c.  The actual
   tables are of variable size and allocated by mac_table.lua.  The
   size of a bucket must be known to access a row in the buckets
   matrix.  There should be no need to change BUCKET_SIZE for
   perfomance reasons, see the comments in mac_table.lua. This
   declaration must match the ctype for hash_table_t in
   mac_table.lua. */
enum { BUCKET_SIZE = 6 };
typedef struct {
  hash_table_header_t h;
  mac_entry_t buckets[1][BUCKET_SIZE];
} hash_table_t;

typedef struct {
  handle_t port;
  handle_t group;
} lookup_result_t;

void mac_table_insert(uint64_t mac, handle_t port, handle_t group,
                      hash_table_t **tables, uint32_t index);
lookup_result_t *mac_table_lookup(uint64_t mac, mac_entry_t *bucket);
void mac_table_lookup_pft(uint64_t mac, mac_entry_t *bucket,
                          handle_t port, handle_t group, struct packet *p,
                          pft_t **pfts, port_list_t *flood_pl);
