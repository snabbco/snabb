int      lock_memory();
void    *allocate_huge_page(int size);
void    *map_physical_ram(uint64_t start, uint64_t end, bool cacheable);
uint64_t phys_page(uint64_t virt_page);

