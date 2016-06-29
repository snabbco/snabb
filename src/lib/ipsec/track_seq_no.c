// See https://tools.ietf.org/html/rfc4303#page-38

#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DEBUG 1

#ifdef DEBUG
#define DBG(FMT, ...) printf("arepl: " FMT "\n", __VA_ARGS__)
#else
#define DBG(FMT, ...)
#endif

/* LO32/HI32: Get lower/upper 32 bit of a 64 bit value.
 * Should be completely portable and endian-independent.
 * It shouldn't be difficult for the compiler to recognize this as
 * division/multiplication by powers of two and hence replace it with
 * bit shifts, automagically in the right direction.
 */
#define LO32(U64) ((uint32_t)((uint64_t)(U64) % 4294967296ull)) // 2**32
#define HI32(U64) ((uint32_t)((uint64_t)(U64) / 4294967296ull)) // 2**32

/* MK64: Likewise, make a 64 bit value from two 32 bit values */
#define MK64(L, H) ((uint64_t)(((uint32_t)(H)) * 4294967296ull + ((uint32_t)(L))))


/* struct arepl_state: Holds the state we need to keep for
 * anti-replay purposes, that is, mainly a "window" of bits
 * representing "have-seen" information about sequence numbers.
 *
 * `win` ends up pointing into an array of size `W`/8 so that
 * it has a total of `W` bits, each representing the information
 * whether we have or have not seen a packet with a particular
 * sequence number.
 *
 * `W` is the window size in bits, `T` is the leading edge of our
 * window, which is by definition the largest sequence number we have
 * seen and verified so far.  The window thus at any given time
 * starts at sequence number `T`-`W`+1 and ends at `T`.
 * Sequence numbers are being mapped to bit positions in `win`
 * simply by calculating <sequence number> % `W`
 */
struct arepl_state
{
	uint8_t *win;

	uint32_t W;
	uint64_t T;
};


// public interface
bool arepl_pass(uint32_t seq_hi, uint32_t seq_lo, struct arepl_state *st);
void arepl_accept(uint32_t seq_hi, uint32_t seq_lo, struct arepl_state *st);
uint32_t arepl_infer_seq_hi(uint32_t seq_lo, struct arepl_state *st);


// local helpers
static void advance_wnd(struct arepl_state *st, uint64_t newT);
static void set_pktbit(struct arepl_state *st, uint64_t seq, bool on);
static bool get_pktbit(struct arepl_state *st, uint64_t seq);



/* arepl_pass: Determine whether a packet with the sequence number
 * made from `seq_hi` and `seq_lo` could be a legitimate packet.
 *
 * "Could", because we can't really tell if the received packet with
 * this sequence number is in fact valid (since we haven't yet
 * integrity-checked it - the sequence number may be spoofed), but we
 * can give an authoritative "no" if we have already seen and accepted
 * a packet with this number.
 *
 * If our answer is NOT "no", the caller will, provided the packet was
 * valid, use arepl_accept() for us to mark the sequence number as seen.
 */
bool
arepl_pass(uint32_t seq_hi, uint32_t seq_lo, struct arepl_state *st)
{
	uint64_t seq = MK64(seq_lo, seq_hi);

	/*
	 * `seq` can never be less than the lower end of our window
	 * because `arepl_infer_seq_hi()` assumes the sender incremented their
	 * upper 32 bit of the sequence number whenever the lower 32 bit
	 * of it are less than the lower 32 bit of T.
	 * So the cases left to check are a) `seq` is inside the window
	 * and b) `seq` is ahead of the window.
	 */

	if (seq <= st->T && get_pktbit(st, seq)) {
		DBG("Rejecting replayed packet seq=%"PRIu64
		    " (hi=%"PRIu32", lo=%"PRIu32"); T=%"PRIu64", W=%"PRIu32,
		    seq, seq_hi, seq_lo, st->T, st->W);

		return false; // replayed, reject
	}

	/*
	 * From a sequence number point of view, this one looks fine;
	 * it is either an old packet we haven't seen yet, or the
	 * next/a future packet.
	 *
	 * Successful decryption later on will tell if the packet (and
	 * hence the sequence number) was legit, at which point arepl_accept()
	 * will be called, the have-seen bit representing this sequence number
	 * will be set and the window possibly advances.
	 */
	return true;
}

/* Signal that the packet received with this sequence number was
 * in fact valid -- we record that we have seen it so as to prevent
 * future replays of it.
 */
void
arepl_accept(uint32_t seq_hi, uint32_t seq_lo, struct arepl_state *st)
{
	uint64_t seq = MK64(seq_lo, seq_hi);

	uint64_t oldT = st->T; // XXX only for the DBG

	if (seq > st->T)
		advance_wnd(st, seq);

	DBG("Accepting packet seq=%"PRIu64
	    " (hi=%"PRIu32", lo=%"PRIu32"); T=%"PRIu64"->%"PRIu64
	    " (+%"PRIu64"), W=%"PRIu32,
	    seq, seq_hi, seq_lo, oldT, st->T, st->T - oldT, st->W);

	set_pktbit(st, seq, 1);
}

/* Guess what the upper 32 bit of a received half sequence number probably
 * was, based on our window position and following the alogrithm in RFC 4303 App. A
 */
uint32_t
arepl_infer_seq_hi(uint32_t seq_lo, struct arepl_state *st)
{
	uint32_t Tl = LO32(st->T);
	uint32_t Th = HI32(st->T);

	if (Tl >= st->W - 1) { // Case A
		if (seq_lo >= Tl - st->W + 1)
			return Th;
		else
			return Th + 1;
	} else { // Case B
		if (seq_lo >= Tl - st->W + 1)
			return Th - 1;
		else
			return Th;
	}
}

// local helpers

/* Advance the window so that the "head" bit corresponds to sequence
 * number `newT`.
 */
static void
advance_wnd(struct arepl_state *st, uint64_t newT)
{
	uint64_t diff = newT - st->T;

	/* For advances greater than the window size, don't clear
	 * more bits than the window has */
	if (diff > st->W)
		diff = st->W;

	uint64_t T = newT;

	/* Clear all bits corresponding to the sequence numbers that used to
	 * be ahead of, but are now inside our window since we haven't seen
	 * them yet */
	while (diff--) {
		//DBG("kill %"PRIu64, T);
		set_pktbit(st, T--, 0);
	}

	/* Advance the window head */
	st->T = newT;
}

/* Set/clear the bit in our window that corresponds to sequence number `seq` */
static inline void
set_pktbit(struct arepl_state *st, uint64_t seq, bool on)
{
	size_t bitno = seq % st->W;
	size_t blockno = bitno / 8;
	bitno %= 8;

	/* First clear the bit, then maybe set it. This way
	 * we don't have to branch on `on` */
	st->win[blockno] &= ~(1u << bitno);
	st->win[blockno] |= (uint8_t)on << bitno;
}

/* Get the bit in our window that corresponds to sequence number `seq` */
static inline bool
get_pktbit(struct arepl_state *st, uint64_t seq)
{
	size_t bitno = seq % st->W;
	size_t blockno = bitno / 8;
	bitno = bitno % 8;

	return st->win[blockno] & (1u << bitno);
}

// done using ffi.C.new now
// struct arepl_state *
// arepl_alloc_state(uint32_t winsz)
// {
// 	struct arepl_state *st = malloc(sizeof *st);
// 	if (!st)
// 		return NULL;
//
// 	st->win = malloc(winsz / 8);
// 	if (!st->win) {
// 		free(st);
// 		return NULL;
// 	}
//
// 	memset(st->win, 0, winsz / 8);
// 	st->W = winsz;
// 	st->T = 0;
//
// 	return st;
// }
//
// void
// arepl_free_state(struct arepl_state *st)
// {
// 	if (st)
// 		free(st->win);
// 	free(st);
// }
