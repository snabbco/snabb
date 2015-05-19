/* IP checksum routine for AVX2.
 *
 * Original code by Tony Rogvall that is
 * copyright 2011 Teclo Networks AG. MIT licensed by Juho Snellman.
 */

#include <stdint.h>
#include <arpa/inet.h>
#include <x86intrin.h>
#include "lib/checksum_lib.h"

// For fallback onto non-SIMD checksum:
extern uint16_t cksum_generic(unsigned char *p, size_t n, uint32_t initial);

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
