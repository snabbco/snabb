
int open_container();
int add_group_to_container(int groupid);
int open_device_from_vfio_group(int groupid, const char* devicename);
uint64_t mmap_memory(void *buffer, uint64_t size, uint64_t iova, uint8_t read, uint8_t write);
void show_device_info(int device);
uint32_t volatile *mmap_region(int device, int n);
size_t pread_config(int device, void *buf, size_t count, int64_t offset);
size_t pwrite_config(int device, void *buf, size_t count, int64_t offset);
