#include <assert.h>
#include <fcntl.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdio.h>
#include <linux/vfio.h>

/// bastarization of assert_perror
#  define assert_perror(errnum)                     \
  (!(errnum)                                \
   ? __ASSERT_VOID_CAST (0)                     \
   : __assert_perror_fail ((errnum), __FILE__, __LINE__, __ASSERT_FUNCTION))

/// uses a single VFIO container, each mmio_group will be added to it.
static int _container = 0;
static int _set_iommu_type = 0;

/**
 * makes sure the static _container variable holds the VFIO container
 */
int open_container()
{
    int cont_fd = 0;

    if (_container != 0)
        return _container;

    /* Create a new container */
    assert((cont_fd = open("/dev/vfio/vfio", O_RDWR)) >= 0);
    assert(ioctl(cont_fd, VFIO_GET_API_VERSION) == VFIO_API_VERSION);
    assert(ioctl(cont_fd, VFIO_CHECK_EXTENSION, VFIO_TYPE1_IOMMU));

    _container = cont_fd;
    return _container;
}

/**
 * adds a new mmio_group to a the container
 */
int add_group_to_container(int groupid)
{
    int group = 0;
    char grouppath[50];
    struct vfio_group_status group_status = { .argsz = sizeof(group_status) };
    struct vfio_iommu_type1_info iommu_info = { .argsz = sizeof(iommu_info) };

    int container = open_container();
    assert(container >= 0);

    /* Open the group */
    sprintf(grouppath, "/dev/vfio/%d", groupid);
    assert((group = open(grouppath, O_RDWR))>=0);

    /* Test the group is viable and available */
    assert_perror(ioctl(group, VFIO_GROUP_GET_STATUS, &group_status));
    assert(group_status.flags & VFIO_GROUP_FLAGS_VIABLE);

    /* Add the group to the container */
    assert_perror(ioctl(group, VFIO_GROUP_SET_CONTAINER, &container));

    /* Enable the IOMMU model we want, only once */
    if (!_set_iommu_type) {
        assert_perror(ioctl(container, VFIO_SET_IOMMU, VFIO_TYPE1_IOMMU));
        _set_iommu_type = 1;
    }

    return group;
}

/**
 * opens a device using an open group descriptor
 */
int open_device_from_vfio_group (int groupfd, const char* devicename)
{
    return ioctl(groupfd, VFIO_GROUP_GET_DEVICE_FD, devicename);
}

/**
 * maps a chunk of memory to a given IOVA on the container's IO space
 */
uint64_t mmap_memory(void *buffer, uint64_t size, uint64_t iova, uint8_t read, uint8_t write)
{
    if (!_container)
        return 0;

    struct vfio_iommu_type1_dma_map dma_map = { .argsz = sizeof(dma_map) };

    dma_map.vaddr = (uint64_t)buffer;
    dma_map.size = size;
    dma_map.iova = iova;
    dma_map.flags = 0 |
        (read ? VFIO_DMA_MAP_FLAG_READ : 0) |
        (write ? VFIO_DMA_MAP_FLAG_WRITE : 0);

    if (ioctl(_container, VFIO_IOMMU_MAP_DMA, &dma_map)) {
        return 0;
    }
    return dma_map.iova;
}



void show_device_info (int device)
{
    int i;
    struct vfio_device_info device_info = { .argsz = sizeof(device_info) };
    /* Test and setup the device */
    assert(ioctl(device, VFIO_DEVICE_GET_INFO, &device_info)==0);
    if (device_info.flags & VFIO_DEVICE_FLAGS_RESET) {
        printf ("device supports RESET\n");
    }
    if (device_info.flags & VFIO_DEVICE_FLAGS_PCI) {
        printf ("it's a PCI device");
    }

    printf ("found %ud regions\n", device_info.num_regions);
    for (i = 0; i < device_info.num_regions; i++) {
        struct vfio_region_info reg = { .argsz = sizeof(reg) };

        reg.index = i;
        assert(ioctl(device, VFIO_DEVICE_GET_REGION_INFO, &reg)==0);
        printf ("region %d (%d) [%llX-%llX]:\n", i, reg.index, reg.offset, reg.size);
        if (reg.flags & VFIO_REGION_INFO_FLAG_READ) {
            printf (" supports read.");
        }
        if (reg.flags & VFIO_REGION_INFO_FLAG_WRITE) {
            printf (" supports write.");
        }
        if (reg.flags & VFIO_REGION_INFO_FLAG_MMAP) {
            printf (" supports mmap.");
        }
        printf ("\n");
    }

    printf ("found %ud interrupts\n", device_info.num_irqs);
    for (i = 0; i < device_info.num_irqs; i++) {
        struct vfio_irq_info irq = { .argsz = sizeof(irq) };

        irq.index = i;
        assert(ioctl(device, VFIO_DEVICE_GET_IRQ_INFO, &irq)==0);
        printf ("irq %d (%d) count:%d", i, irq.index, irq.count);
        if (irq.flags & VFIO_IRQ_INFO_EVENTFD) {
            printf (" eventfd");
        }
        if (irq.flags & VFIO_IRQ_INFO_MASKABLE) {
            printf (" maskable");
        }
        if (irq.flags & VFIO_IRQ_INFO_AUTOMASKED) {
            printf (" automasked");
        }
        if (irq.flags & VFIO_IRQ_INFO_NORESIZE) {
            printf (" noresize");
        }
        printf ("\n");
    }
}


/**
 * maps IO registers of the given region onto virtual memory
 */
uint32_t volatile *mmap_region (int device, int n)
{
    struct vfio_device_info device_info = { .argsz = sizeof(device_info) };
    struct vfio_region_info reg = { .argsz = sizeof(reg) };
    void *ptr = NULL;

    // check if it's a valid region
    assert(ioctl(device, VFIO_DEVICE_GET_INFO, &device_info)==0);
    if (n >= device_info.num_regions) return NULL;

    reg.index = n;
    assert(ioctl(device, VFIO_DEVICE_GET_REGION_INFO, &reg)==0);
    // is this region mmap()able?
    if (! (reg.flags & VFIO_REGION_INFO_FLAG_MMAP)) return NULL;

    ptr = mmap(NULL, reg.size, PROT_READ | PROT_WRITE, MAP_SHARED, device, reg.offset);
    if (ptr == MAP_FAILED) {
        return NULL;
    } else {
        return (uint32_t volatile *)ptr;
    }
}


size_t pread_config (int device, void* buf, size_t count, int64_t offset)
{
    struct vfio_region_info reg = { .argsz = sizeof(reg) };

    reg.index = VFIO_PCI_CONFIG_REGION_INDEX;
    assert(ioctl(device, VFIO_DEVICE_GET_REGION_INFO, &reg)==0);
    return pread(device, buf, count, reg.offset+offset);
}

size_t pwrite_config (int device, void* buf, size_t count, int64_t offset)
{
    struct vfio_region_info reg = { .argsz = sizeof(reg) };

    reg.index = VFIO_PCI_CONFIG_REGION_INDEX;
    assert(ioctl(device, VFIO_DEVICE_GET_REGION_INFO, &reg)==0);
    return pread(device, buf, count, reg.offset+offset);
}

