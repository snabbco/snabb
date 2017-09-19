#include <stdint.h>
#include <stdio.h>

uint16_t lpm4_dxr_search(uint32_t ip, uint16_t *ints, uint16_t *keys, uint32_t *bottoms, uint32_t *tops) {
  uint32_t base = ip >> 16;
  ip = ip & 0xffff;
  int bottom = bottoms[base];
  int top = tops[base];
  int mid = 0;

  if(top <= bottom){
    return keys[top];
  } else if (top - bottom < 32) {
    while(bottom < top && ip <= ints[top-1]){
      top = top - 1;
    }
    return keys[top];
  }else{
    while (bottom < top) {
      mid = bottom + (top-bottom) / 2;
      if(ints[mid] < ip) { bottom = mid + 1; } else { top = mid; }
      mid = bottom + (top-bottom) / 2;
      if(ints[mid] < ip) { bottom = mid + 1; } else { top = mid; }
      mid = bottom + (top-bottom) / 2;
      if(ints[mid] < ip) { bottom = mid + 1; } else { top = mid; }
      mid = bottom + (top-bottom) / 2;
      if(ints[mid] < ip) { bottom = mid + 1; } else { top = mid; }
    }
    return keys[top];
  }
}
