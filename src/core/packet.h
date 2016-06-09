/* Use of this source code is governed by the Apache 2.0 license; see COPYING. */

enum {
    // A few bytes of headroom if needed by a low-level transport like
    // virtio.
    PACKET_HEADROOM_SIZE = 48,
    // The maximum amount of payload in any given packet.
    PACKET_PAYLOAD_SIZE = 10*1024
};

// Packet of network data, with associated metadata.
struct packet {
    unsigned char *data;
    uint16_t length;           // data payload length
    uint16_t headroom;
    uint32_t padding;
    unsigned char data_[PACKET_PAYLOAD_SIZE];
};

