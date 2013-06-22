// A buffer describes a piece of memory with known size and physical address.
struct buffer {
  char *ptr;     // virtual address in this process
  uint64_t phy;  // stable physical address
  uint32_t size; // how many bytes in the buffer?
}

// A packet_iovec describes a portion of a buffer.
struct packet_iovec {
  struct buffer *buffer;
  uint32_t offset;
  uint32_t length;
};

// Maximum number of packet_iovec's per packet.
enum { PACKET_IOVEC_MAX = 16 };

// Packet info (metadata) for checksum and segmentation offload.
//
// This is intentionally bit-compatible with the Virtio structure
// 'virtio_net_hdr' because that seems a reasonable starting point.
struct packet_info {
  uint8_t flags;        // see below
  uint8_t gso_flags;    // see below
  uint16_t hdr_len;     // ethernet + ip + tcp/udp header length
  uint16_t gso_size;    // bytes of post-header payload per segment
  uint16_t csum_start;  // position where checksum starts
  uint16_t csum_offset; // offset (after start) to store checksum
};

// packet_info.flags
enum {
  PACKET_NEEDS_CSUM = 1, // checksum needed
  PACKET_CSUM_VALID = 2  // checksum verified
};

// packet_info.gso_flags
enum {
  PACKET_GSO_NONE  = 0,    // No segmentation needed
  PACKET_GSO_TCPV4 = 1,    // IPv4 TCP segmentation needed
  PACKET_GSO_UDPV4 = 3,    // IPv4 UDP segmentation needed
  PACKET_GSO_TCPV6 = 4,    // IPv6 TCP segmentation needed
  PACKET_GSO_ECN   = 0x80  // TCP has ECN set
};

struct packet {
  int refcount;
  struct packet_header *header;
  struct packet_iovec buffers[PACKET_IOVEC_MAX];
}
