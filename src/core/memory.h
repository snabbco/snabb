int      lock_memory();
void    *allocate_huge_page(int size);
uint64_t phys_page(uint64_t virt_page);

void setup_signal();


struct map_ids_t {
   int huge_page_bits;
   int ids[16384];
} *map_ids;
