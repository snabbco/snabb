/* IP checksum routines.
 *
 * See src/arch/ for architecture specific SIMD versions.
 *
 * Generic checksm routine taken from DPDK: 
 *   BSD license; (C) Intel 2010-2015, 6WIND 2014.
 */

#include <arpa/inet.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/time.h>

uint16_t cksum_generic(unsigned char *p, size_t len, uint16_t initial)
{
  uint32_t sum = htons(initial);
  const uint16_t *u16 = (const uint16_t *)p;

  while (len >= (sizeof(*u16) * 4)) {
    sum += u16[0];
    sum += u16[1];
    sum += u16[2];
    sum += u16[3];
    len -= sizeof(*u16) * 4;
    u16 += 4;
  }
  while (len >= sizeof(*u16)) {
    sum += *u16;
    len -= sizeof(*u16);
    u16 += 1;
  }

  /* if length is in odd bytes */
  if (len == 1)
    sum += *((const uint8_t *)u16);

  while(sum>>16)
    sum = (sum & 0xFFFF) + (sum>>16);
  return ntohs((uint16_t)~sum);
}

// SIMD versions

//
// A unaligned version of the cksum,
// n is number of 16-bit values to sum over, n in it self is a
// 16 bit number in order to avoid overflow in the loop
//
static inline uint32_t cksum_ua_loop(unsigned char *p, uint16_t n)
{
  uint32_t s0 = 0;
  uint32_t s1 = 0;

  while (n) {
    s0 += p[0];
    s1 += p[1];
    p += 2;
    n--;
  }
  return (s0<<8)+s1;
}

// Incrementally update checksum when modifying a 16-bit value.
void checksum_update_incremental_16(uint16_t* checksum_cell,
                                    uint16_t* value_cell,
                                    uint16_t new_value)
{
  uint32_t sum;

  sum = ~ntohs(*checksum_cell) & 0xffff;
  sum += (~ntohs(*value_cell) & 0xffff) + new_value;
  sum = (sum >> 16) + (sum & 0xffff);
  sum += (sum >> 16);

  *checksum_cell = htons(~sum & 0xffff);
  *value_cell = htons(new_value);
}

// Incrementally update checksum when modifying a 32-bit value.
void checksum_update_incremental_32(uint16_t* checksum_cell,
                                    uint32_t* value_cell,
                                    uint32_t new_value)
{
  uint32_t sum;

  uint32_t old_value = ~ntohl(*value_cell);

  sum = ~ntohs(*checksum_cell) & 0xffff;
  sum += (old_value >> 16) + (old_value & 0xffff);
  sum += (new_value >> 16) + (new_value & 0xffff);
  sum = (sum >> 16) + (sum & 0xffff);
  sum += (sum >> 16);

  *checksum_cell = htons(~sum & 0xffff);
  *value_cell = htonl(new_value);
}

// Calculate the TCP Pseudo Header Checksum.
uint32_t tcp_pseudo_checksum(uint16_t *sip, uint16_t *dip,
                             int addr_halfwords, int len)
{
  uint32_t result = 6 /* PKT_IP_PROTO_TCP */ + len;
  int i;
  for(i = 0; i < addr_halfwords; i++) {
    result += ntohs(sip[i]);
    result += ntohs(dip[i]);
  }
  return result;
}

// calculates the initial checksum value resulting from
// the pseudo header.
// return values:
// 0x0000 - 0xFFFF : initial checksum (in network order).
// 0xFFFF0001 : unknown packet (non IPv4/6 or non TCP/UDP)
// 0xFFFF0002 : bad header
uint32_t pseudo_header_initial(const int8_t *buf, size_t len)
{
  const uint16_t const *hwbuf = (const uint16_t *)buf;
  int8_t ipv = (buf[0] & 0xF0) >> 4;
  int8_t proto = 0;
  int headersize = 0;

  if (ipv == 4) {           // IPv4
    proto = buf[9];
    headersize = (buf[0] & 0x0F) * 4;
  } else if (ipv == 6) {    // IPv6
    proto = buf[6];
    headersize = 40;
  } else {
    return 0xFFFF0001;
  }

  if (proto == 6 || proto == 17) {     // TCP || UDP
    uint32_t sum = 0;
    len -= headersize;
    if (ipv == 4) {                         // IPv4
      if (cksum_generic((unsigned char *)buf, headersize, 0) != 0) {
        return 0xFFFF0002;
      }
      sum = htons(len & 0x0000FFFF) + (proto << 8)
              + hwbuf[6]
              + hwbuf[7]
              + hwbuf[8]
              + hwbuf[9];

    } else {                                // IPv6
      sum = hwbuf[2] + (proto << 8);
      int i;
      for (i = 4; i < 20; i+=4) {
        sum += hwbuf[i] +
               hwbuf[i+1] +
               hwbuf[i+2] +
               hwbuf[i+3];
      }
    }
    sum = ((sum & 0xffff0000) >> 16) + (sum & 0xffff);
    sum = ((sum & 0xffff0000) >> 16) + (sum & 0xffff);
    return sum;
  }
  return 0xFFFF0001;
}
