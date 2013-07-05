enum { CANARY_SIZE = 16*1024 };

struct canary {
  uint8_t bytes[CANARY_SIZE];
};

