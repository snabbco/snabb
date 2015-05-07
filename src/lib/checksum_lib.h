/*
 * Checksum library routines that are inline functions.
 * For inclusion by checksum implementations.
 */
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
