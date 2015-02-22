// The maximum amount of payload in any given packet.
enum { PACKET_PAYLOAD_SIZE = 10*1024 };

// Packet of network data, with associated metadata.
struct packet {
    unsigned char data[PACKET_PAYLOAD_SIZE];
    uint16_t length;           // data payload length
    uint16_t flags;            // see packet_flags enum below
    uint16_t csum_start;       // position where checksum starts
    uint16_t csum_offset;      // offset (after start) to store checksum
};

enum packet_flags {
  PACKET_NEEDS_CSUM = 1, // Layer-4 checksum needs to be computed
  PACKET_CSUM_VALID = 2  // checksums are known to be correct
};

