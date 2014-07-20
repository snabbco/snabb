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
static int              cfg_phys_mode;
static int              cfg_tx_align;

#define EVENTS_PER_POLL 64
#define N_BUFS		511
#define BUF_SIZE        2048


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
static int               tx_frame_len;

static uint8_t            local_mac[6];
static uint8_t            remote_mac[6];

static int remain;
static int n_send_remain;

void
show_status(int sig)
{
  static int prev_remain;
  if (remain == prev_remain) {
    printf("exiting\n");
    exit(0);
  }
  printf("n_send_remain: %d remain: %d\n", n_send_remain, remain);
  prev_remain = remain;
}

static void
transmit_buffer(unsigned buf_id)
{
  struct pkt_buf* pb = pkt_bufs[buf_id];
  *((int*)(pb->dma_buf + cfg_tx_align + ETH_HLEN)) = cfg_iter - n_send_remain;
  TRY(ef_vi_transmit_init(&vi, pb->dma_buf_addr, tx_frame_len, buf_id));
  n_send_remain--;
}

static void tx_loop(void)
{
  ef_request_id ids[EF_VI_TRANSMIT_BATCH];
  static volatile long long waste_cycles;
  static long empty_polls;
  static long nonempty_polls;

  remain = cfg_iter;
  n_send_remain = cfg_iter;

  for (int buf_id = 0; buf_id < N_BUFS; buf_id++) {
    transmit_buffer(buf_id);
  }
  ef_vi_transmit_push(&vi);
    
  while (1) {
    ef_event evs[EVENTS_PER_POLL];
    int n_ev = ef_eventq_poll(&vi, evs, EVENTS_PER_POLL);
    int push = 0;

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
          }

          for (int i = 0; i < ((n_tx_done > n_send_remain) ? n_send_remain : n_tx_done); i++) {
            transmit_buffer(ids[i]);
            push = 1;
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

    if (push) {
      ef_vi_transmit_push(&vi);
    }
  }
 done:
  printf("Send polls: %ld Empty: %ld (%.f%%)\n",
         empty_polls + nonempty_polls, empty_polls,
         (double) empty_polls / ((double) (empty_polls + nonempty_polls) / 100.));
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


int init_pkt(void* pkt_buf, int payload_length)
{
  ci_ether_hdr* eth = pkt_buf;

  assert(ETH_HLEN == sizeof(ci_ether_hdr));

  memcpy(eth->ether_shost, local_mac, 6);
  memcpy(eth->ether_dhost, remote_mac, 6);
  eth->ether_type = htons(0x6003);
  {
    char* blurb = "the quick brown fox jumps over the lazy dog ";
    int blurb_len = strlen(blurb);
    char* payload = pkt_buf + sizeof(ci_ether_hdr) + sizeof(int);
    for (int i = 0; i < payload_length; i++) {
      payload[i] = blurb[i % blurb_len];
    }
  }
    
  return ETH_HLEN + payload_length;
}


static void do_init(int ifindex)
{
  enum ef_pd_flags pd_flags = EF_PD_DEFAULT;
  ef_filter_spec filter_spec;
  enum ef_vi_flags vi_flags = 0;
  unsigned char mac[6];

  if (cfg_phys_mode)
    pd_flags |= EF_PD_PHYS_MODE;

  vi_flags |= EF_VI_TX_PUSH_DISABLE;

  /* Allocate virtual interface. */
  TRY(ef_driver_open(&driver_handle));
  TRY(ef_pd_alloc(&pd, driver_handle, ifindex, pd_flags));
  TRY(ef_vi_alloc_from_pd(&vi, driver_handle, &pd, driver_handle,
                          -1, -1, -1, NULL, -1, vi_flags));

  ef_vi_get_mac(&vi, driver_handle, local_mac);
  printf("Local MAC address %02x:%02x:%02x:%02x:%02x:%02x, MTU %d\n",
         local_mac[0], local_mac[1], local_mac[2], local_mac[3], local_mac[4], local_mac[5],
         ef_vi_mtu(&vi, driver_handle));

  {
    int bytes = N_BUFS * BUF_SIZE;
    void* p;
    TEST(posix_memalign(&p, CI_PAGE_SIZE, bytes) == 0);
    TRY(ef_memreg_alloc(&memreg, driver_handle, &pd, driver_handle, p, bytes));
    for (int i = 0; i < N_BUFS; ++i) {
      struct pkt_buf* pb = (void*) ((char*) p + i * BUF_SIZE);
      pb->id = i;
      pb->dma_buf_addr = ef_memreg_dma_addr(&memreg, i * BUF_SIZE);
      pb->dma_buf_addr += MEMBER_OFFSET(struct pkt_buf, dma_buf);
      pkt_bufs[i] = pb;
    }
  }

  for (int i = 0; i < N_BUFS; ++i) {
    struct pkt_buf* pb = pkt_bufs[i];
    pb->dma_buf_addr += cfg_tx_align;
    tx_frame_len = init_pkt(pb->dma_buf + cfg_tx_align, cfg_payload_len);
  }

}

static int parse_interface(const char* s, int* ifindex_out)
{
  char dummy;
  if ((*ifindex_out = if_nametoindex(s)) == 0) {
    if (sscanf(s, "%d%c", ifindex_out, &dummy) != 1) {
      return 0;
    }
  }
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
  fprintf(stderr, "  send [options] <send|recv> <interface> <remote-mac>\n");
  fprintf(stderr, "\noptions:\n");
  fprintf(stderr, "  -n <iterations>         - set number of iterations\n");
  fprintf(stderr, "  -s <message-size>       - set udp payload size\n");
  fprintf(stderr, "  -w <count>              - set tx cycle waste counter\n");
  fprintf(stderr, "  -p                      - physical address mode\n");
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
  int c;

  printf("# ef_vi_version_str: %s\n", ef_vi_version_str());

  while ((c = getopt (argc, argv, "n:s:w:pta:")) != -1)
    switch (c) {
    case 'n':
      cfg_iter = atoi(optarg);
      break;
    case 's':
      cfg_payload_len = atoi(optarg);
      break;
    case 'p':
      cfg_phys_mode = 1;
      break;
    case 'a':
      cfg_tx_align = atoi(optarg);
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

  if (argc != 2)
    usage();
  CL_CHK(parse_interface(argv[0], &ifindex));
  CL_CHK(parse_mac(argv[1], remote_mac));

  signal(SIGINT, show_status);

  printf("# payload len: %d\n", cfg_payload_len);
  printf("# iterations: %d\n", cfg_iter);
  do_init(ifindex);
  printf("# frame len: %d\n", tx_frame_len);
  printf("# tx align: %d\n", cfg_tx_align);
  send_test();
  sleep(1);

  return 0;
}

