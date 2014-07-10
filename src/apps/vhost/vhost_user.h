enum {
    VHOST_USER_MEMORY_MAX_NREGIONS = 8
};

// vhost_user request types
enum {
    VHOST_USER_NONE = 0,
    VHOST_USER_GET_FEATURES = 1,
    VHOST_USER_SET_FEATURES = 2,
    VHOST_USER_SET_OWNER = 3,
    VHOST_USER_RESET_OWNER = 4,
    VHOST_USER_SET_MEM_TABLE = 5,
    VHOST_USER_SET_LOG_BASE = 6,
    VHOST_USER_SET_LOG_FD = 7,
    VHOST_USER_SET_VRING_NUM = 8,
    VHOST_USER_SET_VRING_ADDR = 9,
    VHOST_USER_SET_VRING_BASE = 10,
    VHOST_USER_GET_VRING_BASE = 11,
    VHOST_USER_SET_VRING_KICK = 12,
    VHOST_USER_SET_VRING_CALL = 13,
    VHOST_USER_SET_VRING_ERR = 14,
    VHOST_USER_MAX
};

struct vhost_user_memory_region {
    uint64_t guest_phys_addr;
    uint64_t memory_size;
    uint64_t userspace_addr;
    uint64_t mmap_offset;
};

struct vhost_user_memory {
    uint32_t nregions;
    uint32_t padding;
    struct vhost_user_memory_region regions[VHOST_USER_MEMORY_MAX_NREGIONS];
};

enum {
    VHOST_USER_VERSION_MASK = (0x3),
    VHOST_USER_REPLY_MASK = (0x1 << 2),
    VHOST_USER_VRING_IDX_MASK = (0xff),
    VHOST_USER_VRING_NOFD_MASK = (0x1 << 8)
};

struct vhost_user_msg {
    int request;
    uint32_t flags;
    uint32_t size;
    union {
        uint64_t u64;
        // defined in vhost.h
        struct vhost_vring_state state;
        struct vhost_vring_addr addr;
        struct vhost_user_memory memory;
    };
}__attribute__((packed));

int vhost_user_connect(const char *path);
int vhost_user_listen(const char *path);
int vhost_user_accept(int sock);
int vhost_user_send(int sock, struct vhost_user_msg *msg);
int vhost_user_receive(int sock, struct vhost_user_msg *msg, int *fds,
        int *nfds);
void* vhost_user_map_guest_memory(int fd, uint64_t size);
int vhost_user_unmap_guest_memory(void *ptr, uint64_t size);
int vhost_user_sync_shm(void *ptr, size_t size);
