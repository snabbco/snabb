/*
** Copyright 2005-2014  Solarflare Communications Inc.
**                      7505 Irvine Center Drive, Irvine, CA 92618, USA
** Copyright 2002-2005  Level 5 Networks Inc.
**
** This program is free software; you can redistribute it and/or modify it
** under the terms of version 2 of the GNU General Public License as
** published by the Free Software Foundation.
**
** This program is distributed in the hope that it will be useful,
** but WITHOUT ANY WARRANTY; without even the implied warranty of
** MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
** GNU General Public License for more details.
*/

/*
** Copyright 2005-2014  Solarflare Communications Inc.
**                      7505 Irvine Center Drive, Irvine, CA 92618, USA
** Copyright 2002-2005  Level 5 Networks Inc.
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are
** met:
**
** * Redistributions of source code must retain the above copyright notice,
**   this list of conditions and the following disclaimer.
**
** * Redistributions in binary form must reproduce the above copyright
**   notice, this list of conditions and the following disclaimer in the
**   documentation and/or other materials provided with the distribution.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
** IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
** TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
** PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
** HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
** SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
** TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
** PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
** LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
** NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/


/* efsendrecv
 *
 * Copyright 2009-2010 Solarflare Communications Inc.
 * Author: David Riddoch
 * Date: 2009/10/01
 */

#define _GNU_SOURCE 1

#include <etherfabric/vi.h>
#include <etherfabric/pd.h>
#include <etherfabric/memreg.h>
#include <ci/tools.h>
#include <ci/tools/ippacket.h>
#include <ci/net/ipv4.h>

#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <arpa/inet.h>
#include <sys/time.h>
#include <errno.h>
#include <string.h>
#include <net/if.h>
#include <netdb.h>
#include <math.h>

/* This gives a frame len of 70, which is the same as:
**   eth + ip + tcp + tso + 4 bytes payload
*/
#define DEFAULT_PAYLOAD_SIZE  28

#define CACHE_ALIGN           __attribute__((aligned(EF_VI_DMA_ALIGN)))


static int              cfg_iter = 10000000;
static unsigned		cfg_payload_len = DEFAULT_PAYLOAD_SIZE;
static int              cfg_waste_cycles = 0;
static int              cfg_use_vf;
static int              cfg_phys_mode;
static int              cfg_disable_tx_push;
static int              cfg_tx_align;
static int              cfg_rx_align;

#define N_RX_BUFS	64u
#define N_TX_BUFS	EF_VI_TRANSMIT_BATCH
#define FIRST_TX_BUF    N_RX_BUFS
#define N_BUFS          (N_RX_BUFS + N_TX_BUFS)
#define BUF_SIZE        2048
#define MAX_UDP_PAYLEN	(1500 - sizeof(ci_ip4_hdr) - sizeof(ci_udp_hdr))


#define TEST(x)                                                  \
  do {                                                          \
    if (! (x)) {                                               \
      fprintf(stderr, "ERROR: '%s' failed\n", #x);              \
      fprintf(stderr, "ERROR: at %s:%d\n", __FILE__, __LINE__); \
      exit(1);                                                  \
    }                                                           \
  } while (0)

#define TRY(x)                                                  \
  do {                                                          \
    int __rc = (x);                                             \
    if (__rc < 0) {                                            \
      fprintf(stderr, "ERROR: '%s' failed\n", #x);              \
      fprintf(stderr, "ERROR: at %s:%d\n", __FILE__, __LINE__); \
      fprintf(stderr, "ERROR: rc=%d errno=%d (%s)\n",           \
              __rc, errno, strerror(errno));                    \
      exit(1);                                                  \
    }                                                           \
  } while (0)

#define MEMBER_OFFSET(c_type, mbr_name)  \
  ((uint32_t) (uintptr_t)(&((c_type*)0)->mbr_name))


struct pkt_buf {
  struct pkt_buf* next;
  ef_addr         dma_buf_addr;
  int             id;
  uint8_t         dma_buf[1] CACHE_ALIGN;
};


static ef_driver_handle  driver_handle;
static ef_vi		 vi;

struct pkt_buf*          pkt_bufs[N_BUFS];
static ef_pd             pd;
static ef_memreg         memreg;
static unsigned          rx_posted, rx_completed;
static int               tx_frame_len;

static uint8_t            remote_mac[6];
static struct sockaddr_in sa_local, sa_remote;

static int remain;

static void rx_loop(void)
{
  ef_event      evs[EF_VI_EVENT_POLL_MIN_EVS];
  int           n_ev, i;

  remain = cfg_iter;

  for (int buf_id = 0; buf_id < N_RX_BUFS; buf_id++) {
    TRY(ef_vi_receive_init(&vi, pkt_bufs[buf_id]->dma_buf_addr, buf_id));
    remain--;
  }
  ef_vi_receive_push(&vi);
    
  while (1) {
    n_ev = ef_eventq_poll(&vi, evs, sizeof(evs) / sizeof(evs[0]));
    if (n_ev > 0)
      for (i = 0; i < n_ev; ++i)
        switch (EF_EVENT_TYPE(evs[i])) {
        case EF_EVENT_TYPE_RX:
          TEST(EF_EVENT_RX_SOP(evs[i]) == 1);
          TEST(EF_EVENT_RX_CONT(evs[i]) == 0);
          remain--;
          if (remain <= 0) {
            return;
          }
          {
            int buf_id = EF_EVENT_RX_RQ_ID(evs[i]);
            TRY(ef_vi_receive_init(&vi, pkt_bufs[buf_id]->dma_buf_addr, buf_id));
            ef_vi_receive_push(&vi);
          }
          break;
        case EF_EVENT_TYPE_RX_DISCARD:
          fprintf(stderr, "ERROR: RX_DISCARD type=%d\n",
                  EF_EVENT_RX_DISCARD_TYPE(evs[i]));
          break;
        case EF_EVENT_TYPE_TX_ERROR:
          fprintf(stderr, "ERROR: TX_ERROR type=%d\n",
                  EF_EVENT_TX_ERROR_TYPE(evs[i]));
          break;
        default:
          fprintf(stderr, "ERROR: unexpected event "EF_EVENT_FMT"\n",
                  EF_EVENT_PRI_ARG(evs[i]));
          break;
        }
  }
}

static void tx_loop(void)
{
  ef_request_id ids[EF_VI_TRANSMIT_BATCH];
  static volatile long long waste_cycles;
  static long empty_polls;
  static long nonempty_polls;

  remain = cfg_iter;

  for (int buf_id = 0; buf_id < N_TX_BUFS; buf_id++) {
    ef_vi_transmit(&vi, pkt_bufs[buf_id]->dma_buf_addr, tx_frame_len, buf_id);
    remain--;
  }
    
  while (1) {
    ef_event evs[EF_VI_EVENT_POLL_MIN_EVS];
    int n_ev = ef_eventq_poll(&vi, evs, sizeof(evs) / sizeof(evs[0]));
    for (int i = 0; i < cfg_waste_cycles; i++) {
      waste_cycles += i;
    }
    if (n_ev) {
      nonempty_polls++;
    } else {
      empty_polls++;
    }
    for (int i = 0; i < n_ev; ++i) {
      switch (EF_EVENT_TYPE(evs[i])) {
      case EF_EVENT_TYPE_TX:
        {
          int n_tx_done = ef_vi_transmit_unbundle(&vi, &evs[i], ids);
          remain -= n_tx_done;
          if (remain <= 0) {
            goto done;
          } else if (n_tx_done > remain) {
            n_tx_done = remain;                          /* only send as many frames as requested */
          }
          for (int i = 0; i < n_tx_done; i++) {
            int buf_id = ids[i];
            ef_vi_transmit(&vi, pkt_bufs[buf_id]->dma_buf_addr, tx_frame_len, buf_id);
          }
        }
        break;
      case EF_EVENT_TYPE_TX_ERROR:
        fprintf(stderr, "ERROR: TX_ERROR type=%d\n",
                EF_EVENT_TX_ERROR_TYPE(evs[i]));
        break;
      default:
        fprintf(stderr, "ERROR: unexpected event "EF_EVENT_FMT"\n",
                EF_EVENT_PRI_ARG(evs[i]));
        break;
      }
    }
  }
 done:
  printf("Polls: %ld Empty: %ld (%.f%%)\n",
         empty_polls + nonempty_polls, empty_polls,
         (double) empty_polls / ((double) (empty_polls + nonempty_polls) / 100.));
}

/**********************************************************************/

static void recv_test(void)
{
  struct timeval start, end;

  int i, usec;
  gettimeofday(&start, NULL);
  rx_loop();
  gettimeofday(&end, NULL);

  usec = (end.tv_sec - start.tv_sec) * 1000000;
  usec += end.tv_usec - start.tv_usec;
  printf("packet rate: %.1f Mpps\n", (double) cfg_iter / (double) usec);
}

static void send_test(void)
{
  struct timeval start, end;

  int i, usec;
  gettimeofday(&start, NULL);
  tx_loop();
  gettimeofday(&end, NULL);

  usec = (end.tv_sec - start.tv_sec) * 1000000;
  usec += end.tv_usec - start.tv_usec;
  printf("packet rate: %.1f Mpps\n", (double) cfg_iter / (double) usec);
}


typedef struct {
  const char*   name;
  void        (*fn)(void);
} test_t;

static test_t the_tests[] = {
  { "send",	send_test	},
  { "recv",	recv_test	},
};

#define NUM_TESTS  (sizeof(the_tests) / sizeof(the_tests[0]))


/**********************************************************************/

int init_udp_pkt(void* pkt_buf, int paylen)
{
  int ip_len = sizeof(ci_ip4_hdr) + sizeof(ci_udp_hdr) + paylen;
  ci_ether_hdr* eth;
  ci_ip4_hdr* ip4;
  ci_udp_hdr* udp;

  eth = pkt_buf;
  ip4 = (void*) ((char*) eth + 14);
  udp = (void*) (ip4 + 1);

  memcpy(eth->ether_dhost, remote_mac, 6);
  ef_vi_get_mac(&vi, driver_handle, eth->ether_shost);
  eth->ether_type = htons(0x0800);
  ci_ip4_hdr_init(ip4, CI_NO_OPTS, ip_len, 0, IPPROTO_UDP,
		  sa_local.sin_addr.s_addr,
		  sa_remote.sin_addr.s_addr, 0);
  ci_udp_hdr_init(udp, ip4, sa_local.sin_port,
		  sa_remote.sin_port, udp + 1, paylen, 0);

  return ETH_HLEN + ip_len;
}


static void do_init(int ifindex)
{
  enum ef_pd_flags pd_flags = EF_PD_DEFAULT;
  ef_filter_spec filter_spec;
  enum ef_vi_flags vi_flags = 0;
  int i;

  if (cfg_use_vf)
    pd_flags |= EF_PD_VF;
  if (cfg_phys_mode)
    pd_flags |= EF_PD_PHYS_MODE;
  if (cfg_disable_tx_push)
    vi_flags |= EF_VI_TX_PUSH_DISABLE;

  /* Allocate virtual interface. */
  TRY(ef_driver_open(&driver_handle));
  TRY(ef_pd_alloc(&pd, driver_handle, ifindex, pd_flags));
  TRY(ef_vi_alloc_from_pd(&vi, driver_handle, &pd, driver_handle,
                          -1, -1, -1, NULL, -1, vi_flags));

  ef_filter_spec_init(&filter_spec, EF_FILTER_FLAG_NONE);
  TRY(ef_filter_spec_set_ip4_local(&filter_spec, IPPROTO_UDP,
                                   sa_local.sin_addr.s_addr,
                                   sa_local.sin_port));
  TRY(ef_vi_filter_add(&vi, driver_handle, &filter_spec, NULL));

  {
    int bytes = N_BUFS * BUF_SIZE;
    void* p;
    TEST(posix_memalign(&p, CI_PAGE_SIZE, bytes) == 0);
    TRY(ef_memreg_alloc(&memreg, driver_handle, &pd, driver_handle, p, bytes));
    for (i = 0; i < N_BUFS; ++i) {
      struct pkt_buf* pb = (void*) ((char*) p + i * BUF_SIZE);
      pb->id = i;
      pb->dma_buf_addr = ef_memreg_dma_addr(&memreg, i * BUF_SIZE);
      pb->dma_buf_addr += MEMBER_OFFSET(struct pkt_buf, dma_buf);
      pkt_bufs[i] = pb;
    }
  }

  for (i = 0; i < N_RX_BUFS; ++i) {
    pkt_bufs[i]->dma_buf_addr += cfg_rx_align;
  }

  for (i = FIRST_TX_BUF; i < N_BUFS; ++i) {
    struct pkt_buf* pb = pkt_bufs[i];
    pkt_bufs[i]->dma_buf_addr += cfg_tx_align;
    tx_frame_len = init_udp_pkt(pb->dma_buf + cfg_tx_align, cfg_payload_len);
  }
}


static int my_getaddrinfo(const char* host, const char* port,
                          struct addrinfo**ai_out)
{
  struct addrinfo hints;
  hints.ai_flags = 0;
  hints.ai_family = AF_INET;
  hints.ai_socktype = 0;
  hints.ai_protocol = 0;
  hints.ai_addrlen = 0;
  hints.ai_addr = NULL;
  hints.ai_canonname = NULL;
  hints.ai_next = NULL;
  return getaddrinfo(host, port, &hints, ai_out);
}


static int parse_interface(const char* s, int* ifindex_out)
{
  char dummy;
  if ((*ifindex_out = if_nametoindex(s)) == 0)
    if (sscanf(s, "%d%c", ifindex_out, &dummy) != 1)
      return 0;
  return 1;
}


static int parse_host(const char* s, struct in_addr* ip_out)
{
  const struct sockaddr_in* sin;
  struct addrinfo* ai;
  if (my_getaddrinfo(s, 0, &ai) < 0)
    return 0;
  sin = (const struct sockaddr_in*) ai->ai_addr;
  *ip_out = sin->sin_addr;
  return 1;
}


static int parse_mac(const char* s, uint8_t* m)
{
  unsigned u[6];
  char dummy;
  int i;
  if (sscanf(s, "%x:%x:%x:%x:%x:%x%c",
             &u[0], &u[1], &u[2], &u[3], &u[4], &u[5], &dummy) != 6)
    return 0;
  for (i = 0; i < 6; ++i)
    if ((m[i] = (uint8_t) u[i]) != u[i])
      return 0;
  return 1;
}


static void usage(void)
{
  fprintf(stderr, "\nusage:\n");
  fprintf(stderr, "  efsendrecv [options] <send|recv> <interface>\n"
                  "            <local-ip-intf> <local-port>\n"
                  "            <remote-mac> <remote-ip-intf> <remote-port>\n");
  fprintf(stderr, "\noptions:\n");
  fprintf(stderr, "  -n <iterations>         - set number of iterations\n");
  fprintf(stderr, "  -s <message-size>       - set udp payload size\n");
  fprintf(stderr, "  -w <count>              - set tx cycle waste counter\n");
  fprintf(stderr, "  -v                      - use a VF\n");
  fprintf(stderr, "  -p                      - physical address mode\n");
  fprintf(stderr, "  -t                      - disable TX push\n");
  fprintf(stderr, "\n");
  exit(1);
}


#define CL_CHK(x)                               \
  do{                                           \
    if (! (x))                                 \
      usage();                                  \
  }while(0)


int main(int argc, char* argv[])
{
  int ifindex;
  test_t* t;
  int c;

  printf("# ef_vi_version_str: %s\n", ef_vi_version_str());

  while ((c = getopt (argc, argv, "n:s:w:bvpta:A:")) != -1)
    switch (c) {
    case 'n':
      cfg_iter = atoi(optarg);
      break;
    case 's':
      cfg_payload_len = atoi(optarg);
      break;
    case 'v':
      cfg_use_vf = 1;
      break;
    case 'p':
      cfg_phys_mode = 1;
      break;
    case 't':
      cfg_disable_tx_push = 1;
      break;
    case 'a':
      cfg_tx_align = atoi(optarg);
      break;
    case 'A':
      cfg_rx_align = atoi(optarg);
      break;
    case 'w':
      cfg_waste_cycles = atoi(optarg);
      break;
    case '?':
      usage();
    default:
      TEST(0);
    }

  argc -= optind;
  argv += optind;

  if (argc != 7)
    usage();
  CL_CHK(parse_interface(argv[1], &ifindex));
  CL_CHK(parse_host(argv[2], &sa_local.sin_addr));
  sa_local.sin_port = htons(atoi(argv[3]));
  CL_CHK(parse_mac(argv[4], remote_mac));
  CL_CHK(parse_host(argv[5], &sa_remote.sin_addr));
  sa_remote.sin_port = htons(atoi(argv[6]));

  if (cfg_payload_len > MAX_UDP_PAYLEN) {
    fprintf(stderr, "WARNING: UDP payload length %d is larged than standard "
            "MTU\n", cfg_payload_len);
  }

  for (t = the_tests; t != the_tests + NUM_TESTS; ++t)
    if (! strcmp(argv[0], t->name))
      break;
  if (t == the_tests + NUM_TESTS)
    usage();

  printf("# udp payload len: %d\n", cfg_payload_len);
  printf("# iterations: %d\n", cfg_iter);
  do_init(ifindex);
  printf("# frame len: %d\n", tx_frame_len);
  printf("# rx align: %d\n", cfg_rx_align);
  printf("# tx align: %d\n", cfg_tx_align);
  t->fn();

  return 0;
}

/*! \cidoxg_end */
