// The maximum amount of payload in any given packet.
enum { PACKET_PAYLOAD_SIZE = 10*1024 };

// Packet of network data, with associated metadata.
struct packet {
    unsigned char data[PACKET_PAYLOAD_SIZE];
    uint16_t length;           // data payload length
};

