enum { MAX_MATCHERS = 512 };
enum { MAX_RULES = 32 };

struct match_rule {
  uint16_t offset;
  uint16_t size;
  void *data;
};

struct matcher {
  uint8_t nrules;
  struct match_rule rules[MAX_RULES];
};

int matcher_new(void);
bool matcher_add_rule(uint16_t, uint16_t, uint16_t, void *);
bool matcher_compare(uint16_t, void *, uint16_t);
