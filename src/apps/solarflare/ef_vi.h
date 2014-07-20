module(...,package.seeall); require("ffi").cdef[[
/*
** Copyright 2005-2014  Solarflare Communications Inc.
**                      7505 Irvine Center Drive, Irvine, CA 92618, USA
** Copyright 2002-2005  Level 5 Networks Inc.
**
** This library is free software; you can redistribute it and/or
** modify it under the terms of version 2.1 of the GNU Lesser General Public
** License as published by the Free Software Foundation.
**
** This library is distributed in the hope that it will be useful,
** but WITHOUT ANY WARRANTY; without even the implied warranty of
** MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
** Lesser General Public License for more details.
*/

/****************************************************************************
 * Copyright 2002-2005: Level 5 Networks Inc.
 * Copyright 2005-2008: Solarflare Communications Inc,
 *                      9501 Jeronimo Road, Suite 250,
 *                      Irvine, CA 92618, USA
 *
 * Maintained by Solarflare Communications
 *  <linux-xen-drivers@solarflare.com>
 *  <onload-dev@solarflare.com>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 as published
 * by the Free Software Foundation, incorporated herein by reference.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 ****************************************************************************
 */

/*
 *  \brief  Virtual Interface
 *   \date  2007/05/16
 */


/**********************************************************************
 * Primitive types ****************************************************
 **********************************************************************/

typedef uint32_t                ef_eventq_ptr;
typedef uint64_t                ef_addr;
typedef char*                   ef_vi_ioaddr_t;

static const int EF_VI_MAX_QS              = 32;
static const int EF_VI_EVENT_POLL_MIN_EVS  = 2;

typedef int			ef_request_id;

typedef union {
	uint64_t  u64[1];
	uint32_t  u32[2];
	uint16_t  u16[4];
} ef_vi_qword;

typedef union {
	struct {
		unsigned       type       :16;
	} generic;
	struct {
		unsigned       type       :16;
		unsigned       q_id       :16;
		unsigned       rq_id      :32;
		unsigned       len        :16;
		unsigned       flags      :16;
	} rx;
	struct {  /* This *must* have same initial layout as [rx]. */
		unsigned       type       :16;
		unsigned       q_id       :16;
		unsigned       rq_id      :32;
		unsigned       len        :16;
		unsigned       flags      :16;
		unsigned       subtype    :16;
	} rx_discard;
	struct {
		unsigned       type       :16;
		unsigned       q_id       :16;
		unsigned       desc_id    :16;
	} tx;
	struct {  /* This *must* have same layout as [tx]. */
		unsigned       type       :16;
		unsigned       q_id       :16;
		unsigned       desc_id    :16;
		unsigned       subtype    :16;
	} tx_error;
	struct {
		unsigned       type       :16;
		unsigned       q_id       :16;
	} rx_no_desc_trunc;
	struct {
		unsigned       type       :16;
		unsigned       data;
	} sw;
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

	char*			      vi_mem_mmap_ptr;
	int                           vi_mem_mmap_bytes;
	char*			      vi_io_mmap_ptr;
	int                           vi_io_mmap_bytes;
	int                           vi_clustered;

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
	ef_vi_stats*		      vi_stats;

	struct ef_vi*		      vi_qs[EF_VI_MAX_QS];
	int                           vi_qs_n;

	struct ef_vi_nic_type	      nic_type;

	struct ops {
		int (*transmit)(struct ef_vi*, ef_addr base, int len,
				ef_request_id);
		int (*transmitv)(struct ef_vi*, const ef_iovec*, int iov_len,
				 ef_request_id);
		int (*transmitv_init)(struct ef_vi*, const ef_iovec*,
				      int iov_len, ef_request_id);
		void (*transmit_push)(struct ef_vi*);
		int (*transmit_pio)(struct ef_vi*, ef_addr offset, int len,
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


