#include <time.h>

/* etherfabric/base.h */

typedef int                     ef_driver_handle;

extern int ef_driver_open(ef_driver_handle* dh_out);
extern int ef_driver_close(ef_driver_handle);

/* etherfabric/ef_vi.h */

typedef uint32_t                ef_eventq_ptr;
typedef uint64_t                ef_addr;
typedef char*                   ef_vi_ioaddr_t;

static const int EF_VI_MAX_QS              = 32;
static const int EF_VI_EVENT_POLL_MIN_EVS  = 2;

static const int EVENTS_PER_POLL = 256;

typedef int			ef_request_id;

typedef union {
  uint64_t  u64[1];
  uint32_t  u32[2];
  uint16_t  u16[4];
} ef_vi_qword;

/* LuaJIT does not currently compile code which contains accesses to C
 * bit fields.  As a workaround, we are treating the event structure
 * as union of arrays of the integers that are contained in the
 * structure and access them through LUA helper functions in
 * solarflare.lua.
 */

typedef union {
  struct {
    uint16_t       type;
  } generic;
  struct {
    uint16_t       type;
    uint16_t       q_id;
    uint32_t       rq_id;
    uint16_t       len;
    uint16_t       flags;
  } rx;
  struct {  /* This *must* have same initial layout as [rx]. */
    uint16_t       type;
    uint16_t       q_id;
    uint32_t       rq_id;
    uint16_t       len;
    uint16_t       flags;
    uint16_t       subtype;
  } rx_discard;
  struct {
    uint16_t       type;
    uint16_t       q_id;
    uint16_t       desc_id;
  } tx;
  struct {  /* This *must* have same layout as [tx]. */
    uint16_t       type;
    uint16_t       q_id;
    uint16_t       desc_id;
    uint16_t       subtype;
  } tx_error;
  struct {
    uint16_t       type;
    uint16_t       q_id;
  } rx_no_desc_trunc;
} ef_event;

enum {
  /** Good data was received. */
  EF_EVENT_TYPE_RX,
  /** Packets have been sent. */
  EF_EVENT_TYPE_TX,
  /** Data received and buffer consumed, but something is wrong. */
  EF_EVENT_TYPE_RX_DISCARD,
  /** Transmit of packet failed. */
  EF_EVENT_TYPE_TX_ERROR,
  /** Received packet was truncated due to lack of descriptors. */
  EF_EVENT_TYPE_RX_NO_DESC_TRUNC,
  /** Software generated event. */
  EF_EVENT_TYPE_SW,
  /** Event queue overflow. */
  EF_EVENT_TYPE_OFLOW,
};

static const int EF_EVENT_FLAG_SOP = 0x1;
static const int EF_EVENT_FLAG_CONT = 0x2;
static const int EF_EVENT_FLAG_ISCSI_OK = 0x4;
static const int EF_EVENT_FLAG_MULTICAST = 0x8;

enum {
  EF_EVENT_RX_DISCARD_CSUM_BAD,
  EF_EVENT_RX_DISCARD_MCAST_MISMATCH,
  EF_EVENT_RX_DISCARD_CRC_BAD,
  EF_EVENT_RX_DISCARD_TRUNC,
  EF_EVENT_RX_DISCARD_RIGHTS,
  EF_EVENT_RX_DISCARD_EV_ERROR,
  EF_EVENT_RX_DISCARD_OTHER,
};

enum {
  EF_EVENT_TX_ERROR_RIGHTS,
  EF_EVENT_TX_ERROR_OFLOW,
  EF_EVENT_TX_ERROR_2BIG,
  EF_EVENT_TX_ERROR_BUS,
};

static const int EF_EVENT_SW_DATA_MASK = 0xffff;

typedef struct {
  ef_eventq_ptr	   evq_ptr;
  unsigned	   sync_timestamp_major;
  unsigned	   sync_timestamp_minor;
  unsigned	   sync_timestamp_synchronised;
} ef_eventq_state;

typedef struct {
  ef_addr                       iov_base __attribute__ ((aligned (8)));
  unsigned                      iov_len;
} ef_iovec;

enum ef_vi_flags {
  EF_VI_FLAGS_DEFAULT     = 0x0,
  EF_VI_ISCSI_RX_HDIG     = 0x2,
  EF_VI_ISCSI_TX_HDIG     = 0x4,
  EF_VI_ISCSI_RX_DDIG     = 0x8,
  EF_VI_ISCSI_TX_DDIG     = 0x10,
  EF_VI_TX_PHYS_ADDR      = 0x20,
  EF_VI_RX_PHYS_ADDR      = 0x40,
  EF_VI_TX_IP_CSUM_DIS    = 0x80,
  EF_VI_TX_TCPUDP_CSUM_DIS= 0x100,
  EF_VI_TX_TCPUDP_ONLY    = 0x200,
  EF_VI_TX_FILTER_IP      = 0x400,              /* Siena only */
  EF_VI_TX_FILTER_MAC     = 0x800,              /* Siena only */
  EF_VI_TX_FILTER_MASK_1  = 0x1000,             /* Siena only */
  EF_VI_TX_FILTER_MASK_2  = 0x2000,             /* Siena only */
  EF_VI_TX_FILTER_MASK_3  = (0x1000 | 0x2000),  /* Siena only */
  EF_VI_TX_PUSH_DISABLE   = 0x4000,
  EF_VI_TX_PUSH_ALWAYS    = 0x8000,             /* ef10 only */
  EF_VI_RX_TIMESTAMPS     = 0x10000,            /* ef10 only */
};

typedef struct {
  uint32_t  previous;
  uint32_t  added;
  uint32_t  removed;
} ef_vi_txq_state;

typedef struct {
  uint32_t  prev_added;
  uint32_t  added;
  uint32_t  removed;
  uint32_t  in_jumbo;                           /* ef10 only */
  uint32_t  bytes_acc;                          /* ef10 only */
  uint16_t  rx_ps_pkt_count;                    /* ef10 only */
  uint16_t  rx_ps_credit_avail;                 /* ef10 only */
} ef_vi_rxq_state;

typedef struct {
  uint32_t         mask;
  void*            descriptors;
  uint32_t*        ids;
} ef_vi_txq;

typedef struct {
  uint32_t         mask;
  void*            descriptors;
  uint32_t*        ids;
} ef_vi_rxq;

typedef struct {
  ef_eventq_state  evq;
  ef_vi_txq_state  txq;
  ef_vi_rxq_state  rxq;
  /* Followed by request id fifos. */
} ef_vi_state;

typedef struct {
  uint32_t	rx_ev_lost;
  uint32_t	rx_ev_bad_desc_i;
  uint32_t	rx_ev_bad_q_label;
  uint32_t	evq_gap;
} ef_vi_stats;

enum ef_vi_arch {
  EF_VI_ARCH_FALCON,
  EF_VI_ARCH_EF10,
};

struct ef_vi_nic_type {
  unsigned char  arch;
  char           variant;
  unsigned char  revision;
};

struct ef_pio;

typedef struct ef_vi {
  unsigned                      inited;
  unsigned                      vi_resource_id;
  unsigned                      vi_i;

  unsigned                      rx_buffer_len;
  unsigned                      rx_prefix_len;
  int                           rx_ts_correction;

  char*			        vi_mem_mmap_ptr;
  int                           vi_mem_mmap_bytes;
  char*			        vi_io_mmap_ptr;
  int                           vi_io_mmap_bytes;
  int                           vi_clustered;
  int                           vi_is_packed_stream;
  unsigned                      vi_ps_buf_size;

  ef_vi_ioaddr_t                io;

  struct ef_pio*                linked_pio;

  char*                         evq_base;
  unsigned                      evq_mask;
  unsigned                      timer_quantum_ns;

  unsigned                      tx_push_thresh;

  ef_vi_txq                     vi_txq;
  ef_vi_rxq                     vi_rxq;
  ef_vi_state*                  ep_state;
  enum ef_vi_flags              vi_flags;
  ef_vi_stats*		        vi_stats;

  struct ef_vi*		        vi_qs[32 /* EF_VI_MAX_QS */];
  int                           vi_qs_n;

  struct ef_vi_nic_type	        nic_type;

  struct ops {
    int (*transmit)(struct ef_vi*, ef_addr base, int len,
                    ef_request_id);
    int (*transmitv)(struct ef_vi*, const ef_iovec*, int iov_len,
                     ef_request_id);
    int (*transmitv_init)(struct ef_vi*, const ef_iovec*,
                          int iov_len, ef_request_id);
    void (*transmit_push)(struct ef_vi*);
    int (*transmit_pio)(struct ef_vi*, int offset, int len,
                        ef_request_id dma_id);
    int (*transmit_copy_pio)(struct ef_vi*, int pio_offset,
                             const void* src_buf, int len,
                             ef_request_id dma_id);
    int (*receive_init)(struct ef_vi*, ef_addr, ef_request_id);
    void (*receive_push)(struct ef_vi*);
    int (*eventq_poll)(struct ef_vi*, ef_event*, int evs_len);
    void (*eventq_prime)(struct ef_vi*);
    void (*eventq_timer_prime)(struct ef_vi*, unsigned v);
    void (*eventq_timer_run)(struct ef_vi*, unsigned v);
    void (*eventq_timer_clear)(struct ef_vi*);
    void (*eventq_timer_zero)(struct ef_vi*);
  } ops;
} ef_vi;


enum ef_vi_layout_type {
  EF_VI_LAYOUT_FRAME,
  EF_VI_LAYOUT_MINOR_TICKS,
};

typedef struct {
  enum ef_vi_layout_type   evle_type;
  int                      evle_offset;
  const char*              evle_description;
} ef_vi_layout_entry;

extern int ef_vi_transmit_init(ef_vi*, ef_addr, int bytes, ef_request_id dma_id);

static const int EF_VI_TRANSMIT_BATCH = 64;

extern int ef_vi_transmit_unbundle(ef_vi* ep, const ef_event*, ef_request_id* ids);

extern int ef_vi_state_bytes(ef_vi*);

extern const char* ef_vi_version_str(void);

extern const char* ef_vi_driver_interface_str(void);

extern int ef_vi_receive_query_layout(ef_vi* vi,
                                      const ef_vi_layout_entry**const layout_out,
                                      int* layout_len_out);

extern int ef_vi_receive_get_timestamp(ef_vi* vi, const void* pkt,
				       struct timespec* ts_out);

/* etherfabric/pd.h */

enum ef_pd_flags {
	EF_PD_DEFAULT          = 0x0,
	EF_PD_VF               = 0x1,
	EF_PD_PHYS_MODE        = 0x2,
	EF_PD_RX_PACKED_STREAM = 0x4
};

static const int EF_PD_VLAN_NONE = -1;

typedef struct ef_pd {
	enum ef_pd_flags pd_flags;
	unsigned         pd_resource_id;
        char*            pd_intf_name;

	/* Support for application clusters */
	char*            pd_cluster_name;
	int              pd_cluster_sock;
	ef_driver_handle pd_cluster_dh;
	unsigned         pd_cluster_viset_resource_id;
} ef_pd;

/*! Allocate a protection domain. */
extern int ef_pd_alloc(ef_pd*, ef_driver_handle, int ifindex,
		       enum ef_pd_flags flags);

extern int ef_pd_alloc_by_name(ef_pd*, ef_driver_handle,
                               const char* cluster_or_intf_name,
                               enum ef_pd_flags flags);

extern int ef_pd_alloc_with_vport(ef_pd*, ef_driver_handle,
                                  const char* intf_name,
                                  enum ef_pd_flags flags, int vlan_id);

/*! Unregister a memory region. */
extern int ef_pd_free(ef_pd*, ef_driver_handle);

extern const char* ef_pd_interface_name(ef_pd*);

/* etherfabric/vi.h */

static const int EF_VI_DEFAULT_INTERFACE = -1;

extern int ef_vi_alloc_from_pd(ef_vi* vi,
                               ef_driver_handle vi_dh,
			       struct ef_pd* pd,
                               ef_driver_handle pd_dh,
			       int evq_capacity,
                               int rxq_capacity,
			       int txq_capacity,
			       ef_vi* evq_opt,
                               ef_driver_handle evq_dh,
			       enum ef_vi_flags flags);

extern int ef_vi_free(ef_vi* vi, ef_driver_handle nic);

extern int ef_vi_flush(ef_vi* vi, ef_driver_handle nic);

extern int ef_vi_pace(ef_vi* vi, ef_driver_handle nic, int val);

extern unsigned ef_vi_mtu(ef_vi* vi, ef_driver_handle);

extern int ef_vi_get_mac(ef_vi*, ef_driver_handle, void* mac_out);

extern int ef_eventq_put(unsigned resource_id,
                         ef_driver_handle, unsigned ev_bits);

typedef struct {
	unsigned      vis_res_id;
	struct ef_pd* vis_pd;
} ef_vi_set;

extern int ef_vi_set_alloc_from_pd(ef_vi_set*, ef_driver_handle,
				   struct ef_pd* pd, ef_driver_handle pd_dh,
				   int n_vis);

extern int ef_vi_alloc_from_set(ef_vi* vi, ef_driver_handle vi_dh,
				ef_vi_set* vi_set, ef_driver_handle vi_set_dh,
				int index_in_vi_set, int evq_capacity,
				int rxq_capacity, int txq_capacity,
				ef_vi* evq_opt, ef_driver_handle evq_dh,
				enum ef_vi_flags flags);

enum ef_filter_flags {
	EF_FILTER_FLAG_NONE           = 0x0,
	EF_FILTER_FLAG_REPLACE        = 0x1,
};

typedef struct {
	unsigned type;
	unsigned flags;
	unsigned data[6];
} ef_filter_spec;

enum {
	EF_FILTER_VLAN_ID_ANY = -1,
};

typedef struct {
	int filter_id;
	int filter_type;
} ef_filter_cookie;


extern void ef_filter_spec_init(ef_filter_spec *, enum ef_filter_flags);
extern int ef_filter_spec_set_ip4_local(ef_filter_spec *, int protocol,
					unsigned host_be32, int port_be16);
extern int ef_filter_spec_set_ip4_full(ef_filter_spec *, int protocol,
				       unsigned host_be32, int port_be16,
				       unsigned rhost_be32, int rport_be16);
extern int ef_filter_spec_set_vlan(ef_filter_spec *fs, int vlan_id);
extern int ef_filter_spec_set_eth_local(ef_filter_spec *, int vlan_id,
					const void *mac);
extern int ef_filter_spec_set_unicast_all(ef_filter_spec *);
extern int ef_filter_spec_set_multicast_all(ef_filter_spec *);
extern int ef_filter_spec_set_unicast_mismatch(ef_filter_spec *);
extern int ef_filter_spec_set_multicast_mismatch(ef_filter_spec *);
extern int ef_filter_spec_set_port_sniff(ef_filter_spec *, int promiscuous);
extern int ef_filter_spec_set_tx_port_sniff(ef_filter_spec *);
extern int ef_filter_spec_set_block_kernel(ef_filter_spec *);
extern int ef_filter_spec_set_block_kernel_multicast(ef_filter_spec *);
extern int ef_filter_spec_set_block_kernel_unicast(ef_filter_spec *);

extern int ef_vi_filter_add(ef_vi*, ef_driver_handle, const ef_filter_spec*,
			    ef_filter_cookie *filter_cookie_out);
extern int ef_vi_filter_del(ef_vi*, ef_driver_handle, ef_filter_cookie *);

extern int ef_vi_set_filter_add(ef_vi_set*, ef_driver_handle,
				const ef_filter_spec*,
				ef_filter_cookie *filter_cookie_out);
extern int ef_vi_set_filter_del(ef_vi_set*, ef_driver_handle,
				ef_filter_cookie *);

extern int ef_vi_prime(ef_vi* vi, ef_driver_handle dh, unsigned current_ptr);

/**********************************************************************
 * Get VI stats *******************************************************
 **********************************************************************/

typedef struct {
  char* evsfl_name;
  int   evsfl_offset;
  int   evsfl_size;
} ef_vi_stats_field_layout;

typedef struct {
  int                      evsl_data_size;
  int                      evsl_fields_num;
  ef_vi_stats_field_layout evsl_fields[];
} ef_vi_stats_layout;

/* Retrieve layout for available statistics. */
extern int
ef_vi_stats_query_layout(ef_vi* vi,
                         const ef_vi_stats_layout**const layout_out);

/* Retrieve a set of statistic values.
 *
 * The data size should be equal to evsl_data_bytes from
 * the layout description.
 *
 * If do_reset reset is true, the statistics is reset after reading.
 *
 * Data is provided in little-endian.
 */
extern int
ef_vi_stats_query(ef_vi* vi, ef_driver_handle dh,
                  void* data, int do_reset);


/* etherfabric/memreg.h */

typedef struct ef_memreg {
  unsigned mr_resource_id;
  ef_addr* mr_dma_addrs;
  ef_addr* mr_dma_addrs_base;
} ef_memreg;

extern int ef_memreg_alloc(ef_memreg*, ef_driver_handle,
			   struct ef_pd*, ef_driver_handle pd_dh,
			   void* p_mem, size_t len_bytes);

extern int ef_memreg_free(ef_memreg*, ef_driver_handle);

static const int EF_VI_NIC_PAGE_SIZE = 0x1000;
static const int EF_VI_NIC_PAGE_MASK = 0x0FFF;
static const int CI_PAGE_SIZE = 0x1000;

/* Declarations for the batch polling mechanism */

struct unbundled_tx_request_ids {
  int n_tx_done;
  ef_request_id tx_request_ids[64 /* EF_VI_TRANSMIT_BATCH */];
};

struct device {
  ef_vi* vi;
  int n_ev;
  ef_event events[256 /* EVENTS_PER_POLL */];
  struct unbundled_tx_request_ids unbundled_tx_request_ids[256 /* EVENTS_PER_POLL */];
};

extern void add_device(struct device* device, void* unbundle_function);
extern void drop_device(struct device* device);
extern void poll_devices();
