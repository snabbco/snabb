/* IP checksum routines including x86 SIMD (SSE2 and AVX2).
 * SSE2 code by Tony Rogvall.
 * Copyright 2011 Teclo Networks AG. MIT licensed by Juho Snellman.
 * Generic code taken from DPDK: BSD license; (C) Intel 2010-2014, 6WIND 2014.
 */

#include <arpa/inet.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/time.h>

#include <x86intrin.h>

// Portable C version

static inline uint32_t cksum_generic_loop(const void *buf, size_t len, uint32_t sum)
{
  /* workaround gcc strict-aliasing warning */
  uintptr_t ptr = (uintptr_t)buf;
  const uint16_t *u16 = (const uint16_t *)ptr;

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

  return sum;
}

static inline uint16_t cksum_generic_reduce(uint32_t sum)
{
  sum = ((sum & 0xffff0000) >> 16) + (sum & 0xffff);
  sum = ((sum & 0xffff0000) >> 16) + (sum & 0xffff);
  return (uint16_t)~sum;
}

uint16_t cksum_generic(const void *buf, size_t len, uint16_t initial)
{
  uint32_t sum;

  sum = cksum_generic_loop(buf, len, initial);
  return htons(cksum_generic_reduce(sum));
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

// SSE-2 version

//
// this loop may only run when data is aligned 16 byte aligned
// n is number of 16 byte vectors
//
static inline uint32_t cksum_sse2_loop(unsigned char *p, size_t n)
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

uint16_t cksum_sse2(unsigned char *p, size_t n, uint32_t initial)
{
  uint32_t sum = initial;

  if (n < 128) { return cksum_generic(p, n, initial); }
  int unaligned = (unsigned long) p & 0xf;
  if (unaligned) {
    size_t k = (0x10 - unaligned) >> 1;
    sum += cksum_ua_loop(p, k);
    n -= (2*k);
    p += (2*k);
  }
  if (n >= 32) {  // fast even with only two vectors
    size_t k = (n >> 4);
    sum += cksum_sse2_loop(p, k);
    n -= (16*k);
    p += (16*k);
  }
  if (n > 1) {
    size_t k = (n>>1);   // number of 16-bit words
    sum += cksum_ua_loop(p, k);
    n -= (2*k);
    p += (2*k);
  }
  if (n)       // take care of left over byte
    sum += (p[0] << 8);
  while(sum>>16)
    sum = (sum & 0xFFFF) + (sum>>16);
  return (uint16_t)~sum;
}

// AVX2 version

static inline uint32_t cksum_avx2_loop(unsigned char *p, size_t n)
{
    __m256i sum0, sum1, zero;
    uint32_t s[8] __attribute__((aligned(32))); // aligned for avx2 store
    uint32_t sum2;

    zero = _mm256_set_epi64x(0,0,0,0);
    sum0 = zero;
    sum1 = zero;

    while(n) {
        size_t k = (n >= 0xff) ? 0xff : n;
        __m256i t0,t1;
        __m256i s0 = zero;
        __m256i s1 = zero;
        n -= k;
        while (k) {
            __m256i src = _mm256_load_si256((__m256i const*) p);
            __m256i t;

            t = _mm256_unpacklo_epi8(src, zero);
            s0 = _mm256_adds_epu16(s0, t);
            t = _mm256_unpackhi_epi8(src, zero);
            s1 = _mm256_adds_epu16(s1, t);
            p += sizeof(src);
            k--;
        }

        // LOW - combine S0 and S1 into sum0
        t0 = _mm256_unpacklo_epi16(s0, zero);
        sum0 = _mm256_add_epi32(sum0, t0);
        t1 = _mm256_unpacklo_epi16(s1, zero);
        sum1 = _mm256_add_epi32(sum1, t1);

        // HIGH - combine S0 and S1 into sum1
        t0 = _mm256_unpackhi_epi16(s0, zero);
        sum0 = _mm256_add_epi32(sum0, t0);
        t1 = _mm256_unpackhi_epi16(s1, zero);
        sum1 = _mm256_add_epi32(sum1, t1);
    }
    // here we must sum the 4-32 bit sums into one 32 bit sum
    _mm256_store_si256((__m256i*)s, sum0);
    sum2 = (s[0]<<8) + s[1] + (s[2]<<8) + s[3] + (s[4]<<8) + s[5] + (s[6]<<8) + s[7];
    _mm256_store_si256((__m256i*)s, sum1);
    sum2 += (s[0]<<8) + s[1] + (s[2]<<8) + s[3] + (s[4]<<8) + s[5] + (s[6]<<8) + s[7];

    return sum2;
}

uint16_t cksum_avx2(unsigned char *p, size_t n, uint32_t initial)
{
    uint32_t sum = initial;

    if (n < 128) { return cksum_generic(p, n, initial); }
    int unaligned = (unsigned long) p & 31;
    if (unaligned) {
        size_t k = (32 - unaligned) >> 1;
        sum += cksum_ua_loop(p, k);
        n -= (2*k);
        p += (2*k);
    }
    if (n >= 64) {
        size_t k = (n >> 5);
        sum += cksum_avx2_loop(p, k);
        n -= (32*k);
        p += (32*k);
    }
    if (n > 1) {
        size_t k = (n>>1);   // number of 16-bit words
        sum += cksum_ua_loop(p, k);
        n -= (2*k);
        p += (2*k);
    }
    if (n)       // take care of left over byte
        sum += (p[0] << 8);
    while(sum>>16)
        sum = (sum & 0xFFFF) + (sum>>16);
    return (uint16_t)~sum;
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

