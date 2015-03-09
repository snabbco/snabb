/* x86/SIMD ip checksum routine
 * Written by Tony Rogvall.
 * Signed-off with MIT license by Juho Snellman.
 * Copyright 2011 Teclo Networks AG
 */

#include <arpa/inet.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/time.h>

#include <x86intrin.h>

//
// A unaligned version of the ipsum,
// n is number of 16-bit values to sum over, n in it self is a 
// 16 bit number in order to avoid overflow in the loop
//
static inline uint32_t ipsum_ua_loop(unsigned char *p, uint16_t n)
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

// SSE-2 version
#include <emmintrin.h>

//
// this loop may only run when data is aligned 16 byte aligned
// n is number of 16 byte vectors
//
static inline uint32_t ipsum_sse_loop(unsigned char *p, size_t n)
{
  __m128i sum0, sum1, zero;
  uint32_t s[4];
  uint32_t sum2;

  zero = _mm_set_epi32(0,0,0,0);
  sum0 = zero;
  sum1 = zero;

  while(n) {
    size_t k = (n >= 0xff) ? 0xff : n;
    __m128i t0,t1;
    __m128i s0 = zero;
    __m128i s1 = zero;
    n -= k;
    while (k) {
      __m128i src = _mm_load_si128((__m128i const*) p);
      __m128i t;

      t = _mm_unpacklo_epi8(src, zero);
      s0 = _mm_adds_epu16(s0, t);
      t = _mm_unpackhi_epi8(src, zero);
      s1 = _mm_adds_epu16(s1, t);
      p += sizeof(src);
      k--;
    }

    // LOW - combine S0 and S1 into sum0
    t0 = _mm_unpacklo_epi16(s0, zero);
    sum0 = _mm_add_epi32(sum0, t0);
    t1 = _mm_unpacklo_epi16(s1, zero);
    sum1 = _mm_add_epi32(sum1, t1);

    // HIGH - combine S0 and S1 into sum1
    t0 = _mm_unpackhi_epi16(s0, zero);
    sum0 = _mm_add_epi32(sum0, t0);
    t1 = _mm_unpackhi_epi16(s1, zero);
    sum1 = _mm_add_epi32(sum1, t1);
  }
  // here we must sum the 4-32 bit sums into one 32 bit sum
  _mm_store_si128((__m128i*)s, sum0);
  sum2 = (s[0]<<8) + s[1] + (s[2]<<8) + s[3];
  _mm_store_si128((__m128i*)s, sum1);
  sum2 += (s[0]<<8) + s[1] + (s[2]<<8) + s[3];
  return sum2;
}

uint16_t ipsum_sse(unsigned char *p, size_t n, uint32_t initial)
{
  uint32_t sum = initial;

  int unaligned = (unsigned long) p & 0xf;
  if (unaligned) {
    size_t k = (0x10 - unaligned) >> 1;
    sum += ipsum_ua_loop(p, k);
    n -= (2*k);
    p += (2*k);
  }
  if (n >= 32) {  // fast even with only two vectors
    size_t k = (n >> 4);
    sum += ipsum_sse_loop(p, k);
    n -= (16*k);
    p += (16*k);
  }
  if (n > 1) {
    size_t k = (n>>1);   // number of 16-bit words
    sum += ipsum_ua_loop(p, k);
    n -= (2*k);
    p += (2*k);
  }
  if (n)       // take care of left over byte
    sum += (p[0] << 8);
  while(sum>>16)
    sum = (sum & 0xFFFF) + (sum>>16);
  return (uint16_t)~sum;
}

void update_checksum(unsigned char *buffer, int len, uint32_t initial, int cksum_pos)
{
  uint16_t *cksum_ptr = (uint16_t *) (((unsigned char *)buffer) + cksum_pos);
  *cksum_ptr = 0;             /* zero checksum before computing */
  uint16_t csum = ipsum_sse(buffer, len, initial);
  *cksum_ptr = htons(csum);
}

uint16_t calc_checksum(unsigned char *buffer, int len, uint32_t initial, int cksum_pos)
{
  uint16_t *cksum_ptr = (uint16_t *) (((unsigned char *)buffer) + cksum_pos);
  uint16_t save;
  uint16_t csum;

  save = *cksum_ptr;
  *cksum_ptr = 0;             /* zero checksum before computing */
  csum = ipsum_sse(buffer, len, initial);
  *cksum_ptr = save;

  return csum;
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

