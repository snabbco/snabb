// Calculate and store a ones-complement ip checksum.
void update_checksum(unsigned char *buffer, int len, uint32_t initial, int cksum_pos);

// Calculate and return a ones-complement ip checksum.
uint16_t calc_checksum(unsigned char *buffer, int len, uint32_t initial, int cksum_pos)

// Incrementally update checksum when modifying a 16-bit value.
void checksum_update_incremental_16(uint16_t* checksum_cell,
                                    uint16_t* value_cell,
                                    uint16_t new_value);

// Incrementally update checksum when modifying a 32-bit value.
void checksum_update_incremental_32(uint16_t* checksum_cell,
                                    uint32_t* value_cell,
                                    uint32_t new_value);
