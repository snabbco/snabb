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
    VHOST_USER_NET_SET_BACKEND = 15,
    VHOST_USER_MAX
};

struct vhost_user_msg {
  int request;
  int flags;
  union {
    uint64_t u64;
    int fd;
    // defined in vhost.h
    struct vhost_vring_state state;
    struct vhost_vring_addr addr;
    struct vhost_vring_file file;
    struct vhost_memory memory;
  };
  int nfds;
  int fds[VHOST_MEMORY_MAX_NREGIONS];
};


int vhost_user_open_socket(const char *path);
int vhost_user_accept(int sock);
int vhost_user_send(int sock, struct vhost_user_msg *msg);
int vhost_user_receive(int sock, struct vhost_user_msg *msg);
void* map_guest_memory(int fd, int size);
int unmap_guest_memory(void *ptr, int size);
int sync_shm(void *ptr, size_t size);
