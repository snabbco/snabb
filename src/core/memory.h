int      lock_memory();
void    *allocate_huge_page(int size);
void    *allocate_huge_page_numa(int size, int numa_node);
uint64_t phys_page(uint64_t virt_page);

