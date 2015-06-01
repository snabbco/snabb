// Calculate IP checksum using SSE2 instructions.
// (This will crash if you call it on a CPU that does not support SSE.)
uint16_t cksum_sse2(unsigned char *p, size_t n, uint16_t initial);

// Calculate IP checksum using AVX2 instructions.
// (This will crash if you call it on a CPU that does not support AVX2.)
uint16_t cksum_avx2(unsigned char *p, size_t n, uint16_t initial);

// Calculate IP checksum using portable C code.
// This works on all hardware.
uint16_t cksum_generic(unsigned char *p, size_t n, uint16_t initial);

// Incrementally update checksum when modifying a 16-bit value.
void checksum_update_incremental_16(uint16_t* checksum_cell,
                                    uint16_t* value_cell,
                                    uint16_t new_value);

// Incrementally update checksum when modifying a 32-bit value.
void checksum_update_incremental_32(uint16_t* checksum_cell,
                                    uint32_t* value_cell,
                                    uint32_t new_value);

uint32_t tcp_pseudo_checksum(uint16_t *sip, uint16_t *dip,
                             int addr_halfwords, int len);

uint32_t pseudo_header_initial(const int8_t *buf, size_t len);
