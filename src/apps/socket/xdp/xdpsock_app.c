// Use of this source code is governed by the Apache 2.0 license; see COPYING.
//
// Heavily based on: https://github.com/torvalds/linux/blob/master/samples/bpf/xdpsock_user.c

/* Power-of-2 number of sockets */
#define MAX_SOCKS 1

/* Round-robin receive */
#define RR_LB 0

#ifndef SOL_XDP
#define SOL_XDP 283
#endif

#ifndef AF_XDP
#define AF_XDP 44
#endif

#ifndef PF_XDP
#define PF_XDP AF_XDP
#endif

#define NUM_FRAMES 131072
#define FRAME_HEADROOM 0
#define FRAME_SHIFT 11
#define FRAME_SIZE 2048
#define NUM_DESCS 1024
#define BATCH_SIZE 1

#define FQ_NUM_DESCS 1024
#define CQ_NUM_DESCS 1024

#define DEBUG_HEXDUMP 0

#define lassert(expr)                                      \
    do {                                                   \
        if (!(expr)) {                                     \
            fprintf(stderr, "%s:%s:%i: Assertion failed: " \
                #expr ": errno: %d/\"%s\"\n",              \
                __FILE__, __func__, __LINE__,              \
                errno, strerror(errno));                   \
            exit(EXIT_FAILURE);                            \
        }                                                  \
    } while (0)


#include <assert.h>
#include <errno.h>
#include <libgen.h>
#include <linux/bpf.h>
#include <linux/if_link.h>
#include <linux/if_xdp.h>
#include <linux/if_ether.h>
#include <net/if.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <net/ethernet.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/mman.h>
#include <unistd.h>
#include <pthread.h>
#include <locale.h>
#include <sys/types.h>
#include <poll.h>

#include "bpf/libbpf.h"
#include "bpf_util.h"
#include <bpf/bpf.h>

#include "xdpsock_app.h"

#define barrier() __asm__ __volatile__("": : :"memory")
#ifdef __aarch64__
#define u_smp_rmb() __asm__ __volatile__("dmb ishld": : :"memory")
#define u_smp_wmb() __asm__ __volatile__("dmb ishst": : :"memory")
#else
#define u_smp_rmb() barrier()
#define u_smp_wmb() barrier()
#endif
#define likely(x) __builtin_expect(!!(x), 1)
#define unlikely(x) __builtin_expect(!!(x), 0)

/* Private. */
static inline u32 umem_nb_free(struct xdp_umem_uqueue *q, u32 nb);
static inline u32 xq_nb_free(struct xdp_uqueue *q, u32 ndescs);
static inline u32 umem_nb_avail(struct xdp_umem_uqueue *q, u32 nb);
static inline u32 xq_nb_avail(struct xdp_uqueue *q, u32 ndescs);
static inline int umem_fill_to_kernel_ex(struct xdp_umem_uqueue *fq, struct xdp_desc *d, size_t nb);
static inline int umem_fill_to_kernel(struct xdp_umem_uqueue *fq, u64 *d, size_t nb);
static inline size_t umem_complete_from_kernel(struct xdp_umem_uqueue *cq, u64 *d, size_t nb);
static inline void *xq_get_data(struct xdpsock *xsk, u64 addr);
static inline int xq_enq(struct xdp_uqueue *uq, const struct xdp_desc *descs, unsigned int ndescs);
static inline int xq_enq_transmit(struct xdp_uqueue *uq, unsigned int id, unsigned int ndescs, size_t len);
static inline int xq_deq(struct xdp_uqueue *uq, struct xdp_desc *descs, int ndescs);
static struct xdp_umem *xdp_umem_configure(int sfd);
static struct xdpsock *xsk_configure(const xdpsock_options_t *opts, struct xdp_umem *umem);
static void kick_tx(int fd);
static inline void complete_transmit(struct xdpsock *xsk);
static xdpsock_context_t* init_xdpsock_context(const xdpsock_options_t *opts, int xsks_map);

static inline u32 umem_nb_free(struct xdp_umem_uqueue *q, u32 nb)
{
    u32 free_entries = q->cached_cons - q->cached_prod;

    if (free_entries >= nb)
        return free_entries;

    /* Refresh the local tail pointer */
    q->cached_cons = *q->consumer + q->size;

    return q->cached_cons - q->cached_prod;
}

static inline u32 xq_nb_free(struct xdp_uqueue *q, u32 ndescs)
{
    u32 free_entries = q->cached_cons - q->cached_prod;

    if (free_entries >= ndescs)
        return free_entries;

    /* Refresh the local tail pointer */
    q->cached_cons = *q->consumer + q->size;
    return q->cached_cons - q->cached_prod;
}

static inline u32 umem_nb_avail(struct xdp_umem_uqueue *q, u32 nb)
{
    u32 entries = q->cached_prod - q->cached_cons;

    if (entries == 0) {
        q->cached_prod = *q->producer;
        entries = q->cached_prod - q->cached_cons;
    }

    return (entries > nb) ? nb : entries;
}

static inline u32 xq_nb_avail(struct xdp_uqueue *q, u32 ndescs)
{
    u32 entries = q->cached_prod - q->cached_cons;

    if (entries == 0) {
        q->cached_prod = *q->producer;
        entries = q->cached_prod - q->cached_cons;
    }

    return (entries > ndescs) ? ndescs : entries;
}

static inline int umem_fill_to_kernel_ex(struct xdp_umem_uqueue *fq,
                     struct xdp_desc *d,
                     size_t nb)
{
    u32 i;

    if (umem_nb_free(fq, nb) < nb)
        return -ENOSPC;

    for (i = 0; i < nb; i++) {
        u32 idx = fq->cached_prod++ & fq->mask;

        fq->ring[idx] = d[i].addr;
    }

    u_smp_wmb();

    *fq->producer = fq->cached_prod;

    return 0;
}

static inline int umem_fill_to_kernel(struct xdp_umem_uqueue *fq, u64 *d, size_t nb)
{
    u32 i;

    if (umem_nb_free(fq, nb) < nb)
        return -ENOSPC;

    for (i = 0; i < nb; i++) {
        u32 idx = fq->cached_prod++ & fq->mask;

        fq->ring[idx] = d[i];
    }

    u_smp_wmb();

    *fq->producer = fq->cached_prod;

    return 0;
}

static inline size_t umem_complete_from_kernel(struct xdp_umem_uqueue *cq, u64 *d, size_t nb)
{
    u32 idx, i, entries = umem_nb_avail(cq, nb);

    u_smp_rmb();

    for (i = 0; i < entries; i++) {
        idx = cq->cached_cons++ & cq->mask;
        d[i] = cq->ring[idx];
    }

    if (entries > 0) {
        u_smp_wmb();

        *cq->consumer = cq->cached_cons;
    }

    return entries;
}

static inline void *xq_get_data(struct xdpsock *xsk, u64 addr)
{
    return &xsk->umem->frames[addr];
}

static inline int xq_enq(struct xdp_uqueue *uq, const struct xdp_desc *descs, unsigned int ndescs)
{
    struct xdp_desc *r = uq->ring;
    unsigned int i;

    if (xq_nb_free(uq, ndescs) < ndescs)
        return -ENOSPC;

    for (i = 0; i < ndescs; i++) {
        u32 idx = uq->cached_prod++ & uq->mask;

        r[idx].addr = descs[i].addr;
        r[idx].len = descs[i].len;
    }

    u_smp_wmb();

    *uq->producer = uq->cached_prod;
    return 0;
}

static inline int xq_enq_transmit(struct xdp_uqueue *uq,
                 unsigned int id, unsigned int ndescs, size_t len)
{
    struct xdp_desc *r = uq->ring;
    unsigned int i;

    if (xq_nb_free(uq, ndescs) < ndescs)
        return -ENOSPC;

    for (i = 0; i < ndescs; i++) {
        u32 idx = uq->cached_prod++ & uq->mask;

        r[idx].addr = (id + i) << FRAME_SHIFT;
        r[idx].len = len - 1;
    }

    u_smp_wmb();

    *uq->producer = uq->cached_prod;
    return 0;
}

static inline int xq_deq(struct xdp_uqueue *uq,
             struct xdp_desc *descs,
             int ndescs)
{
    struct xdp_desc *r = uq->ring;
    unsigned int idx;
    int i, entries;

    entries = xq_nb_avail(uq, ndescs);

    u_smp_rmb();

    for (i = 0; i < entries; i++) {
        idx = uq->cached_cons++ & uq->mask;
        descs[i] = r[idx];
    }

    if (entries > 0) {
        u_smp_wmb();

        *uq->consumer = uq->cached_cons;
    }

    return entries;
}

static struct xdp_umem *xdp_umem_configure(int sfd)
{
    int fq_size = FQ_NUM_DESCS, cq_size = CQ_NUM_DESCS;
    struct xdp_mmap_offsets off;
    struct xdp_umem_reg mr;
    struct xdp_umem *umem;
    socklen_t optlen;
    void *bufs;

    umem = calloc(1, sizeof(*umem));
    lassert(umem);

    lassert(posix_memalign(&bufs, getpagesize(), /* PAGE_SIZE aligned */
                   NUM_FRAMES * FRAME_SIZE) == 0);

    mr.addr = (__u64)bufs;
    mr.len = NUM_FRAMES * FRAME_SIZE;
    mr.chunk_size = FRAME_SIZE;
    mr.headroom = FRAME_HEADROOM;

    lassert(setsockopt(sfd, SOL_XDP, XDP_UMEM_REG, &mr, sizeof(mr)) == 0);
    lassert(setsockopt(sfd, SOL_XDP, XDP_UMEM_FILL_RING, &fq_size,
               sizeof(int)) == 0);
    lassert(setsockopt(sfd, SOL_XDP, XDP_UMEM_COMPLETION_RING, &cq_size,
               sizeof(int)) == 0);

    optlen = sizeof(off);
    lassert(getsockopt(sfd, SOL_XDP, XDP_MMAP_OFFSETS, &off,
               &optlen) == 0);

    umem->fq.map = mmap(0, off.fr.desc +
                FQ_NUM_DESCS * sizeof(u64),
                PROT_READ | PROT_WRITE,
                MAP_SHARED | MAP_POPULATE, sfd,
                XDP_UMEM_PGOFF_FILL_RING);
    lassert(umem->fq.map != MAP_FAILED);

    umem->fq.mask = FQ_NUM_DESCS - 1;
    umem->fq.size = FQ_NUM_DESCS;
    umem->fq.producer = umem->fq.map + off.fr.producer;
    umem->fq.consumer = umem->fq.map + off.fr.consumer;
    umem->fq.ring = umem->fq.map + off.fr.desc;
    umem->fq.cached_cons = FQ_NUM_DESCS;

    umem->cq.map = mmap(0, off.cr.desc +
                 CQ_NUM_DESCS * sizeof(u64),
                 PROT_READ | PROT_WRITE,
                 MAP_SHARED | MAP_POPULATE, sfd,
                 XDP_UMEM_PGOFF_COMPLETION_RING);
    lassert(umem->cq.map != MAP_FAILED);

    umem->cq.mask = CQ_NUM_DESCS - 1;
    umem->cq.size = CQ_NUM_DESCS;
    umem->cq.producer = umem->cq.map + off.cr.producer;
    umem->cq.consumer = umem->cq.map + off.cr.consumer;
    umem->cq.ring = umem->cq.map + off.cr.desc;

    umem->frames = bufs;
    umem->fd = sfd;

    return umem;
}

static struct xdpsock *xsk_configure(const xdpsock_options_t *opts, struct xdp_umem *umem)
{
    struct sockaddr_xdp sxdp = {};
    struct xdp_mmap_offsets off;
    int sfd, ndescs = NUM_DESCS;
    struct xdpsock *xsk;
    bool shared = true;
    socklen_t optlen;
    u64 i;

    sfd = socket(PF_XDP, SOCK_RAW, 0);
    lassert(sfd >= 0);

    xsk = calloc(1, sizeof(*xsk));
    lassert(xsk);

    xsk->sfd = sfd;
    xsk->outstanding_tx = 0;

    if (!umem) {
        shared = false;
        xsk->umem = xdp_umem_configure(sfd);
    } else {
        xsk->umem = umem;
    }

    lassert(setsockopt(sfd, SOL_XDP, XDP_RX_RING,
               &ndescs, sizeof(int)) == 0);
    lassert(setsockopt(sfd, SOL_XDP, XDP_TX_RING,
               &ndescs, sizeof(int)) == 0);
    optlen = sizeof(off);
    lassert(getsockopt(sfd, SOL_XDP, XDP_MMAP_OFFSETS, &off,
               &optlen) == 0);

    /* Rx */
    xsk->rx.map = mmap(NULL,
               off.rx.desc +
               NUM_DESCS * sizeof(struct xdp_desc),
               PROT_READ | PROT_WRITE,
               MAP_SHARED | MAP_POPULATE, sfd,
               XDP_PGOFF_RX_RING);
    lassert(xsk->rx.map != MAP_FAILED);

    if (!shared) {
        for (i = 0; i < NUM_DESCS * FRAME_SIZE; i += FRAME_SIZE)
            lassert(umem_fill_to_kernel(&xsk->umem->fq, &i, 1)
                == 0);
    }

    /* Tx */
    xsk->tx.map = mmap(NULL,
               off.tx.desc +
               NUM_DESCS * sizeof(struct xdp_desc),
               PROT_READ | PROT_WRITE,
               MAP_SHARED | MAP_POPULATE, sfd,
               XDP_PGOFF_TX_RING);
    lassert(xsk->tx.map != MAP_FAILED);

    xsk->rx.mask = NUM_DESCS - 1;
    xsk->rx.size = NUM_DESCS;
    xsk->rx.producer = xsk->rx.map + off.rx.producer;
    xsk->rx.consumer = xsk->rx.map + off.rx.consumer;
    xsk->rx.ring = xsk->rx.map + off.rx.desc;

    xsk->tx.mask = NUM_DESCS - 1;
    xsk->tx.size = NUM_DESCS;
    xsk->tx.producer = xsk->tx.map + off.tx.producer;
    xsk->tx.consumer = xsk->tx.map + off.tx.consumer;
    xsk->tx.ring = xsk->tx.map + off.tx.desc;
    xsk->tx.cached_cons = NUM_DESCS;

    sxdp.sxdp_family = PF_XDP;
    sxdp.sxdp_ifindex = opts->opt_ifindex;
    sxdp.sxdp_queue_id = opts->opt_queue;

    if (shared) {
        sxdp.sxdp_flags = XDP_SHARED_UMEM;
        sxdp.sxdp_shared_umem_fd = umem->fd;
    } else {
        sxdp.sxdp_flags = opts->opt_xdp_bind_flags;
    }

    lassert(bind(sfd, (struct sockaddr *)&sxdp, sizeof(sxdp)) == 0);

    return xsk;
}

static void kick_tx(int fd)
{
    int ret;

    ret = sendto(fd, NULL, 0, MSG_DONTWAIT, NULL, 0);
    if (ret >= 0 || errno == ENOBUFS || errno == EAGAIN || errno == EBUSY)
        return;
    lassert(0);
}

static inline void complete_transmit(struct xdpsock *xsk)
{
    u64 descs[BATCH_SIZE];
    unsigned int rcvd;

    if (!xsk->outstanding_tx)
        return;

    kick_tx(xsk->sfd);

    rcvd = umem_complete_from_kernel(&xsk->umem->cq, descs, BATCH_SIZE);
    if (rcvd > 0) {
        xsk->outstanding_tx -= rcvd;
        xsk->tx_npkts += rcvd;
    }
}

static unsigned int if_index_by_name(const char *if_name)
{
    unsigned int ret = if_nametoindex(if_name);
    if (!ret) {
        fprintf(stderr, "ERROR: interface \"%s\" does not exist\n", if_name);
        exit(EXIT_FAILURE);
    }
    return ret;
}

static int init_bpf(xdpsock_options_t *opts, const char *filename)
{
    char xdp_filename[256];
    struct rlimit r = {RLIM_INFINITY, RLIM_INFINITY};
    struct bpf_prog_load_attr prog_load_attr = {
        .prog_type    = BPF_PROG_TYPE_XDP,
    };
    int prog_fd, qidconf_map, xsks_map;
    struct bpf_object *obj;
    struct bpf_map *map;
    int ret, key = 0;

    if (setrlimit(RLIMIT_MEMLOCK, &r)) {
        fprintf(stderr, "ERROR: setrlimit(RLIMIT_MEMLOCK) \"%s\"\n",
            strerror(errno));
        exit(EXIT_FAILURE);
    }

    snprintf(xdp_filename, sizeof(xdp_filename), "obj/apps/socket/xdp/%s_kern.o", filename);
    prog_load_attr.file = xdp_filename;

    if (bpf_prog_load_xattr(&prog_load_attr, &obj, &prog_fd))
        exit(EXIT_FAILURE);
    if (prog_fd < 0) {
        fprintf(stderr, "ERROR: no program found: %s\n",
            strerror(prog_fd));
        exit(EXIT_FAILURE);
    }

    map = bpf_object__find_map_by_name(obj, "qidconf_map");
    qidconf_map = bpf_map__fd(map);
    if (qidconf_map < 0) {
        fprintf(stderr, "ERROR: no qidconf map found: %s\n",
            strerror(qidconf_map));
        exit(EXIT_FAILURE);
    }

    map = bpf_object__find_map_by_name(obj, "xsks_map");
    xsks_map = bpf_map__fd(map);
    if (xsks_map < 0) {
        fprintf(stderr, "ERROR: no xsks map found: %s\n",
            strerror(xsks_map));
        exit(EXIT_FAILURE);
    }

    opts->opt_ifindex = if_index_by_name(opts->opt_if);
    if (bpf_set_link_xdp_fd(opts->opt_ifindex, prog_fd, opts->opt_xdp_flags) < 0) {
        fprintf(stderr, "ERROR: link set xdp fd failed\n");
        exit(EXIT_FAILURE);
    }

    ret = bpf_map_update_elem(qidconf_map, &key, &opts->opt_queue, 0);
    if (ret) {
        fprintf(stderr, "ERROR: bpf_map_update_elem qidconf\n");
        exit(EXIT_FAILURE);
    }

    return xsks_map;
}

xdpsock_context_t* init_xdp(const char *if_name)
{
    xdpsock_options_t opts = {
        .opt_bench = 0,
        .opt_poll = 1,
        .opt_queue = 0,
        .opt_xdp_flags = 0,
    };
    opts.opt_if = if_name;

    int xsks_map = init_bpf(&opts, "xdpsock");
    return init_xdpsock_context(&opts, xsks_map);
}

static xdpsock_context_t* init_xdpsock_context(const xdpsock_options_t *opts, int xsks_map)
{
    int i, key, ret;
    struct xdpsock *xsks[MAX_SOCKS];
    int num_socks = 0;

    xdpsock_context_t *ctx = (xdpsock_context_t*) malloc(sizeof(xdpsock_context_t)); 

    /* Create sockets... */
    xsks[num_socks++] = xsk_configure(opts, NULL);

#if RR_LB
    for (i = 0; i < MAX_SOCKS - 1; i++)
        xsks[num_socks++] = xsk_configure(opts, xsks[0]->umem);
#endif

    /* ...and insert them into the map. */
    for (i = 0; i < num_socks; i++) {
        key = i;
        ret = bpf_map_update_elem(xsks_map, &key, &xsks[i]->sfd, 0);
        if (ret) {
            fprintf(stderr, "ERROR: bpf_map_update_elem %d\n", i);
            exit(EXIT_FAILURE);
        }
    }

    for (int i = 0; i < num_socks; i++) {
        ctx->xsks[i] = xsks[i];
    }
    ctx->num_socks = num_socks;
    ctx->opts = opts;
    ctx->nfds_out = 1;
    ctx->fds_out = (struct pollfd*) calloc(sizeof(struct pollfd), ctx->nfds_out + 1);
    ctx->fds_out[0].fd = ctx->xsks[0]->sfd;
    ctx->fds_out[0].events = POLLOUT;
    ctx->nfds_in = 1;
    ctx->fds_in = (struct pollfd*) calloc(sizeof(struct pollfd), ctx->nfds_in + 1);
    ctx->fds_in[0].fd = ctx->xsks[0]->sfd;
    ctx->fds_in[0].events = POLLIN;

    return ctx;
}

bool can_receive(const xdpsock_context_t *ctx)
{
	const unsigned int timeout = 1000;

    return poll(ctx->fds_in, ctx->nfds_in, timeout) > 0;
}

size_t receive_packet(const xdpsock_context_t *ctx, char *data)
{
    struct xdp_desc descs[BATCH_SIZE];
    unsigned int rcvd, i;

    struct xdpsock *xsk = ctx->xsks[0];

    rcvd = xq_deq(&xsk->rx, descs, BATCH_SIZE);
    if (!rcvd) {
        return 0;
	}

	char *buffer = xq_get_data(xsk, descs[0].addr);
	size_t len = descs[0].len;
	memcpy(data, buffer, len);

    xsk->rx_npkts += rcvd;

    umem_fill_to_kernel_ex(&xsk->umem->fq, descs, rcvd);

	return len;
}

void transmit_packets(const xdpsock_context_t *ctx, const char *pkt_data, size_t len, size_t batch_size)
{
    unsigned int idx = 0;

    struct xdpsock *xsk = ctx->xsks[0];

    if (xq_nb_free(&xsk->tx, batch_size) >= batch_size) {
        for (int i = idx*FRAME_SIZE; i < (idx + batch_size)*FRAME_SIZE; i += FRAME_SIZE) {
            memcpy(&xsk->umem->frames[i], pkt_data, len);
        }
        lassert(xq_enq_transmit(&xsk->tx, idx, batch_size, len) == 0);

        xsk->outstanding_tx += batch_size;
        idx += batch_size;
        idx %= NUM_FRAMES;
    }

    complete_transmit(xsk);
}

void transmit_packet(const xdpsock_context_t *ctx, const char *pkt_data, size_t len)
{   
    transmit_packets(ctx, pkt_data, len, 1);
}

void transmit(const xdpsock_context_t *ctx, const char *pkt_data, size_t len)
{
    int timeout, nfds = 1;
    struct pollfd fds[nfds + 1];
    unsigned int idx = 0;

    struct xdpsock *xsk = ctx->xsks[0];

    for (int i = 0; i < NUM_FRAMES * FRAME_SIZE; i += FRAME_SIZE)
        memcpy(&xsk->umem->frames[i], pkt_data, len);

    if (ctx->opts->opt_poll) {
        if (!can_transmit(ctx)) {
            return;
        }
    }

    if (xq_nb_free(&xsk->tx, BATCH_SIZE) >= BATCH_SIZE) {
        lassert(xq_enq_transmit(&xsk->tx, idx, BATCH_SIZE, len) == 0);

        xsk->outstanding_tx += BATCH_SIZE;
        idx += BATCH_SIZE;
        idx %= NUM_FRAMES;
    }

    complete_transmit(xsk);
}

bool can_transmit(const xdpsock_context_t *ctx)
{
    const struct xdpsock *xsk = ctx->xsks[0];
    const int timeout = 1000;

    int ret = poll(ctx->fds_out, ctx->nfds_out, timeout);
    if (ret <= 0) {
        return false;
    }
    if (ctx->fds_out[0].fd != xsk->sfd ||
            !(ctx->fds_out[0].revents & POLLOUT)) {
        return false;
    }
    return true;
}
