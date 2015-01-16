int      lock_memory();
void    *allocate_huge_page(int size, bool persistent);
uint64_t phys_page(uint64_t virt_page);

