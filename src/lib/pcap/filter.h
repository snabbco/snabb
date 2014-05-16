struct bpf_program {
  uint8_t bf_len;
  void *bf_insns;
};

struct pcap_pkthdr {
  /* record header */
  uint32_t ts_sec;         /* timestamp seconds */
  uint32_t ts_usec;        /* timestamp microseconds */
  uint32_t incl_len;       /* number of octets of packet saved in file */
  uint32_t orig_len;       /* actual length of packet */
};

void *pcap_open_dead(int, int);
int pcap_compile(void *, struct bpf_program *, char *, int, uint32_t);
int pcap_offline_filter(struct bpf_program *, struct pcap_pkthdr *, char *);
char * pcap_geterr(void *);
