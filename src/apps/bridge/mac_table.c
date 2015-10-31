#include <inttypes.h>
#include "learning.h"

/* Insert a MAC address into the main and shadow hash tables. */
void mac_table_insert(uint64_t mac, handle_t port, handle_t group,
                      hash_table_t **tables, uint32_t index) {
  int i, j;
  hash_table_t *table;
  mac_entry_t *me;

  /* Iterate over the main (tables[0]) and shadow (tables[1]) hash
     tables. */
  for (i=0; i<=1; i++) {
    table = tables[i];
    for (j = 0; j<BUCKET_SIZE; j++) {
      me = &table->buckets[index][j];
      if (me->mac == 0ULL) {
        /* We found a free slot.  Store the address/port mapping and
           update the table's statistics. */
        if (j == 0) {
          table->h.ubuckets = table->h.ubuckets+1;
        }
        table->h.entries = table->h.entries+1;
        me->mac = mac;
        me->port = port;
        me->group = group;
        break;
      }
      if (me->mac == mac) {
        /* The address is already stored.  Update the port mapping.
           If we wanted to somehow detect addresses flapping between
           ports, this would be the place to do it.*/
        me->port = port;
        me->group = group;
        break;
      }
    }
    if (j == BUCKET_SIZE) {
      /* There are no free slots in this bucket.  The address is
      dropped and the overflow is signalled to the table maintenance
      function, which will try to allocate a bigger table. */
      table->h.overflow = 1;
    }
  }
}

/* Search for a MAC address in a given hash bucket and return the
   associated egress port and group.  A miss is signalled by setting
   the port to 0.
*/
lookup_result_t *mac_table_lookup(uint64_t mac, mac_entry_t *bucket) {
  int i;
  mac_entry_t *me;
  static lookup_result_t result;

  result.port = 0;
  for (i = 0; i<BUCKET_SIZE && bucket[i].mac != 0ULL; i++) {
    me = &bucket[i];
    if (me->mac == mac) {
      result.port = me->port;
      result.group = me->group;
      break;
    }
  }
  return &result;
}

/* Search for a MAC address in a given hash bucket and fill in the
   next free entry in one of the packet forwarding tables based on the
   result.

   If an entry is found, the packet is added to the unicast forwarding
   table (pfts[0]), otherwise it is added to the multicast/flooding
   forwarding table (pfts[1]) by referencing the pre-constructed
   flooding port list. If the ingress port is in the same
   split-horizon group as the egress port or the ingress and egress
   port coincide, the packet is added to the discard table
   (pft[2]). */
void mac_table_lookup_pft(uint64_t mac, mac_entry_t *bucket,
                          handle_t port, handle_t group, struct packet *p,
                          pft_t **pfts, port_list_t *flood_pl) {
  int i;
  pft_t *pft;
  pft_entry_t *pfe;
  mac_entry_t *me;

  for (i = 0; i<BUCKET_SIZE && bucket[i].mac != 0ULL; i++) {
    me = &bucket[i];
    if (me->mac == mac) {
      if ((group != 0 && group == me->group) || port == me->port) {
        /* Discard */
        pft = pfts[2];
        pfe = &pft->entries[pft->length];
        pfe->p = p;
        pft->length++;
        return;
      }
      /* Unicast forwarding.  We don't need to set pfe->plist->length
         here because it has been initialized to 1 when the port list
         was created in apps/bridge/learning.lua. */
      pft = pfts[0];
      pfe = &pft->entries[pft->length];
      pfe->p = p;
      pfe->plist->ports[0] = me->port;
      pft->length++;
      return;
    }
  }
  /* Flooding */
  pft = pfts[1];
  pfe = &pft->entries[pft->length];
  pfe->p = p;
  pfe->plist = flood_pl;
  pft->length++;
}
