// A buffer describes a piece of memory with known size and physical address.
struct color {
  uint16_t kind;
  union {
    struct {
      uint16_t node;
    } numa;
    struct {
      uint16_t device;
      uint16_t descriptor_index;
    } vhost;
  } info;
};

struct buffer_origin {
  enum buffer_origin_type {
    ORIGIN_UNKNOWN = 0,
    ORIGIN_VIRTIO  = 1
    // NUMA...
  } type;
  union buffer_origin_info {
    struct buffer_origin_info_virtio {
      int16_t device_id;
      int16_t descriptor_index;
    } virtio;
  } info;
};

struct buffer {
  char     *pointer; // virtual address in this process
  uint64_t physical; // stable physical address
  uint32_t size;     // how many bytes in the buffer?
  struct origin origin;
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
  // How much "fuel" does this packet have left before it's dropped?
  // This is like the Time-To-Live (TTL) IP header field.
  int32_t fuel;
  int32_t color;
  struct packet_info info;
  int niovecs;
  int length;
  struct packet_iovec iovecs[PACKET_IOVEC_MAX];
};
