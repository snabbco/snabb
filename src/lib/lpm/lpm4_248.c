#include <stdint.h>
#include <stdio.h>

uint16_t lpm4_248_search(uint32_t ip, uint16_t *big, uint16_t *little){
  uint16_t v = big[ip >> 8];
  if(v > 0x8000) { return little[((v - 0x8000) << 8) + (ip & 0xff)]; } else { return v; }
}

uint32_t lpm4_248_search32(uint32_t ip, uint32_t *big, uint32_t *little){
  uint32_t v = big[ip >> 8];
  if(v > 0x80000000) { return little[((v - 0x80000000) << 8) + (ip & 0xff)]; } else { return v; }
}
