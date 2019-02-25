/* Use of this source code is governed by the Apache 2.0 license; see COPYING. */

// See https://tools.ietf.org/html/rfc4303#page-38

#include <stdbool.h>
#include <stdint.h>

/* LO32/HI32: Get lower/upper 32 bit of a 64 bit value. Should be completely
   portable and endian-independent. It shouldn't be difficult for the compiler
   to recognize this as division/multiplication by powers of two and hence
   replace it with bit shifts, automagically in the right direction. */
#define LO32(U64) ((uint32_t)((uint64_t)(U64) % 4294967296ull)) // 2**32
#define HI32(U64) ((uint32_t)((uint64_t)(U64) / 4294967296ull)) // 2**32

/* MK64: Likewise, make a 64 bit value from two 32 bit values */
#define MK64(L, H) ((uint64_t)(((uint32_t)(H)) * 4294967296ull + ((uint32_t)(L))))


/* Set/clear the bit in our window that corresponds to sequence number `seq` */
static inline void set_bit (bool on, uint64_t seq,
                            uint8_t* window, uint32_t W) {
  uint32_t bitno = seq % W;
  uint32_t blockno = bitno / 8;
  bitno %= 8;

  /* First clear the bit, then maybe set it. This way we don't have to branch
     on `on` */
  window[blockno] &= ~(1u << bitno);
  window[blockno] |= (uint8_t)on << bitno;
}

/* Get the bit in our window that corresponds to sequence number `seq` */
static inline bool get_bit (uint64_t seq,
                            uint8_t *window, uint32_t W) {
  uint32_t bitno = seq % W;
  uint32_t blockno = bitno / 8;
  bitno = bitno % 8;

  return window[blockno] & (1u << bitno);
}

/* Advance the window so that the "head" bit corresponds to sequence
 * number `seq`.  Clear all bits for the new sequence numbers that are
 * now considered in-window.
 */
static void advance_window (uint64_t seq,
                            uint64_t T, uint8_t* window, uint32_t W) {
  uint64_t diff = seq - T;

  /* For advances greater than the window size, don't clear more bits than the
     window has */
  if (diff > W) diff = W;

  /* Clear all bits corresponding to the sequence numbers that used to be ahead
     of, but are now inside our window since we haven't seen them yet */
  while (diff--) set_bit(0, seq--, window, W);
}


/* Determine whether a packet with the sequence number made from
 * `seq_hi` and `seq_lo` (where `seq_hi` is inferred from our window
 *  state) could be a legitimate packet.
 *
 * "Could", because we can't really tell if the received packet with
 * this sequence number is in fact valid (since we haven't yet
 * integrity-checked it - the sequence number may be spoofed), but we
 * can give an authoritative "no" if we have already seen and accepted
 * a packet with this number.
 *
 * If our answer is NOT "no", the caller will, provided the packet was
 * valid, use track_seq_no() for us to mark the sequence number as seen.
 */
int64_t check_seq_no (uint32_t seq_lo,
                      uint64_t T, uint8_t *window, uint32_t W) {
  uint32_t Tl = LO32(T);
  uint32_t Th = HI32(T);
  uint32_t seq_hi;
  uint64_t seq;

  if (Tl >= W - 1) { // Case A
    if (seq_lo >= Tl - W + 1) seq_hi = Th;
    else                      seq_hi = Th + 1;
  } else {           // Case B
    if (seq_lo >= Tl - W + 1) seq_hi = Th - 1;
    else                      seq_hi = Th;
  }
  seq = MK64(seq_lo, seq_hi);
  if (seq <= T && get_bit(seq, window, W)) return -1;
  else                                     return seq_hi;
}

/* Signal that the packet received with this sequence number was
 * in fact valid -- we record that we have seen it so as to prevent
 * future replays of it.
 */
uint64_t track_seq_no (uint32_t seq_hi, uint32_t seq_lo,
                       uint64_t T, uint8_t *window, uint32_t W) {
  uint64_t seq = MK64(seq_lo, seq_hi);

  if (seq > T) {
    advance_window(seq, T, window, W);
    T = seq;
  }
  set_bit(1, seq, window, W);
  return T;
}
