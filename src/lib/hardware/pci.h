/* Use of this source code is governed by the Apache 2.0 license; see COPYING. */

int open_pci_resource(const char *path);
void close_pci_resource(int fd, uint32_t *addr);
uint32_t *map_pci_resource(int fd);
int open_pcie_config(const char *path);
