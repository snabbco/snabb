#include <stddef.h>

/*
 * Written by Matthias Drochner <drochner@NetBSD.org>.
 * Public domain.
 */

int
consttime_memequal(const void *b1, const void *b2, size_t len)
{
	const char *c1 = b1, *c2 = b2;
	int res = 0;

	while (len --)
		res |= *c1++ ^ *c2++;

	/*
	 * If the compiler for your favourite architecture generates a
	 * conditional branch for `!res', it will be a data-dependent
	 * branch, in which case this should be replaced by
	 *
	 *	return (1 - (1 & ((res - 1) >> 8)));
	 *
	 * or rewritten in assembly.
	 */
	return !res;
}
