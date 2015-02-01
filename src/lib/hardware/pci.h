int open_pci_resource(const char *path);
void close_pci_resource(int fd, uint32_t volatile *addr);
uint32_t volatile *map_pci_resource(int fd);
int open_pcie_config(const char *path);
