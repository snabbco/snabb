// Buffers can be treated specially depending on their origin.
//
// For example, buffers belonging to Virtio devices need to be
// returned to the device when freed.

struct buffer;

struct buffer_origin {
  enum buffer_origin_type {
    BUFFER_ORIGIN_UNKNOWN = 0,
    BUFFER_ORIGIN_VIRTIO  = 1
    // NUMA...
  } type;
  union buffer_origin_info {
    struct buffer_origin_info_virtio {
      int16_t device_id;
      int16_t ring_id;
      int16_t header_id;
      char    *header_pointer;  // virtual address in this process
      uint32_t total_size;      // how many bytes in all buffers
    } virtio;
  } info;
};

// A buffer describes a piece of memory with known size and physical address.
struct buffer {
  unsigned char *pointer; // virtual address in this process
  uint64_t physical; // stable physical address
  uint32_t size;     // how many bytes in the buffer?
  struct buffer_origin origin;
  uint16_t refcount;  // Counter for references from packets
};

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
  int32_t refcount;
  int32_t color;
  struct packet_info info;
  int niovecs;
  int length;
  struct packet_iovec iovecs[PACKET_IOVEC_MAX];
} __attribute__ ((aligned(64)));
