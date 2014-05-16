#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include "matcher.h"

/* This is the static list of matchers and the global counter of the number of matchers in use */
static struct matcher matchers[MAX_MATCHERS];
static uint16_t nmatchers = 0;

int matcher_new() {
  int m = nmatchers;

  if (m == MAX_MATCHERS) {
    return(-1);
  }
  nmatchers = nmatchers + 1;
  return(m);
}

bool matcher_add_rule(uint16_t m, uint16_t offset, uint16_t size, void *data) {
  struct matcher *matcher = &matchers[m];
  struct match_rule *rule;
  uint8_t nrules = matcher->nrules;

  if (nrules == MAX_RULES) {
    return(false);
  }
  rule = &matcher->rules[nrules];
  rule->offset = offset;
  rule->size = size;
  rule->data = data;
  matcher->nrules++;
  return(true);
}

bool matcher_compare(uint16_t m, void *mem, uint16_t size) {
  struct matcher *matcher = &matchers[m];
  struct match_rule *rule;
  int i;

  for (i=0; i < matcher->nrules; i++) {
    rule = &matcher->rules[i];
    if (rule->offset + rule->size > size) {
      return(false);
    }
    if (memcmp(mem + rule->offset, rule->data, rule->size) != 0) {
      return(false);
    }
  }
  return(true);
}
