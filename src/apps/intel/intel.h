// RX descriptor written by software.
struct rx_desc {
   uint64_t address;    // 64-bit address of receive buffer
   uint64_t dd;         // low bit must be 0, otherwise reserved
} __attribute__((packed));

// RX writeback descriptor written by hardware.
struct rx_desc_wb {
   // uint32_t rss;
   uint16_t checksum;
   uint16_t id;
   uint32_t mrq;
   uint32_t status;
   uint16_t length;
   uint16_t vlan;
} __attribute__((packed));

union rx {
   struct rx_desc data;
   struct rx_desc_wb wb;
} __attribute__((packed));

// TX Extended Data Descriptor written by software.
struct tx_desc {
   uint64_t address;
   uint64_t options;
} __attribute__((packed));

struct tx_context_desc {
   unsigned int tucse:16,
                tucso:8,
                tucss:8,
                ipcse:16,
                ipcso:8,
                ipcss:8,
                mss:16,
                hdrlen:8,
                rsv:2,
                sta:4,
                tucmd:8,
                dtype:4,
                paylen:20;
} __attribute__((packed));

union tx {
   struct tx_desc data;
   struct tx_context_desc ctx;
};
