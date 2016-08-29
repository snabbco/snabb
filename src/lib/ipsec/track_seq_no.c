#include <stdint.h>

// See https://tools.ietf.org/html/rfc4303#page-38
// This is a only partial implementation that attempts to keep track of the
// ESN counter, but does not detect replayed packets.
uint32_t track_seq_no (uint32_t seq_no, uint32_t Tl, uint32_t Th, uint32_t W) {
  if (Tl >= W - 1) { // Case A
    if (seq_no >= Tl - W + 1) return Th;
    else                      return Th + 1;
  } else {           // Case B
    if (seq_no >= Tl - W + 1) return Th - 1;
    else                      return Th;
  }
}
