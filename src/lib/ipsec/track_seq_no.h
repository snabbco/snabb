struct arepl_state;

// done using ffi.C.new now
//struct arepl_state *arepl_alloc_state(uint32_t winsz);
//void arepl_free_state(struct arepl_state *st);

bool arepl_pass(uint32_t seq_hi, uint32_t seq_lo, struct arepl_state *st);
void arepl_accept(uint32_t seq_hi, uint32_t seq_lo, struct arepl_state *st);
uint32_t arepl_infer_seq_hi(uint32_t seq_lo, struct arepl_state *st);
