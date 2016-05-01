/* Use of this source code is governed by the Apache 2.0 license; see COPYING. */
/* IP checksum routines. */

#include <arpa/inet.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/time.h>

uint16_t cksum(unsigned char *p, size_t len, uint16_t initial)
{
  uint64_t sum = htons(initial);
  uint64_t sum1 = 0;
  const uint32_t *u32 = (const uint32_t *)p;

  while (len >= (sizeof(*u32) * 2)) {
    sum  += u32[0];
    sum1 += u32[1];
    u32 += 2;
    len -= sizeof(*u32) * 2;
  }
  sum += sum1;

  const uint16_t *u16 = (const uint16_t *)u32;
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


