// Use of this source code is governed by the Apache 2.0 license; see COPYING.

typedef uint64_t u64;
typedef uint32_t u32;

enum benchmark_type {
    BENCH_RXDROP = 0,
    BENCH_TXONLY = 1,
};

struct xdp_umem_uqueue {
    u32 cached_prod;
    u32 cached_cons;
    u32 mask;
    u32 size;
    u32 *producer;
    u32 *consumer;
    u64 *ring;
    void *map;
};

struct xdp_umem {
    char *frames;
    struct xdp_umem_uqueue fq;
    struct xdp_umem_uqueue cq;
    int fd;
};

struct xdp_uqueue {
    u32 cached_prod;
    u32 cached_cons;
    u32 mask;
    u32 size;
    u32 *producer;
    u32 *consumer;
    struct xdp_desc *ring;
    void *map;
};

struct xdpsock {
    struct xdp_uqueue rx;
    struct xdp_uqueue tx;
    int sfd;
    struct xdp_umem *umem;
    u32 outstanding_tx;
    unsigned long rx_npkts;
    unsigned long tx_npkts;
    unsigned long prev_rx_npkts;
    unsigned long prev_tx_npkts;
};

typedef struct packet_t {
    char* data;
    size_t len;
} __attribute__((packed)) packet_t;

typedef struct xdpsock_options_t {
    enum benchmark_type opt_bench;
    u32 opt_xdp_flags;
    const char *opt_if;
    int opt_ifindex;
    int opt_queue;
    int opt_poll;
    int opt_shared_packet_buffer;
    int opt_interval;
    u32 opt_xdp_bind_flags;
} xdpsock_options_t;

typedef struct xdpsock_context_t {
    struct xdpsock *xsks[4];  // MAX_SOCKS.
    int num_socks;
    int nfds_in, nfds_out;
    struct pollfd *fds_in;
    struct pollfd *fds_out;
    const xdpsock_options_t *opts;
} __attribute__((packed)) xdpsock_context_t;

/* Public. */
xdpsock_context_t* init_xdp(const char *if_name);
bool can_receive(const xdpsock_context_t *ctx);
bool can_transmit(const xdpsock_context_t *ctx);
size_t receive_packet(const xdpsock_context_t *ctx, void* packet);
size_t receive_packets(const xdpsock_context_t *ctx, void** packets, size_t batch_size);
void transmit_packet(const xdpsock_context_t *ctx, void* packet);
void transmit_packets(const xdpsock_context_t *ctx, void** packets, size_t batch_size);
