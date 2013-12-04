#include <unistd.h>
#include <sys/socket.h>

int vhost_user_open_socket(char *path) {
  int socket;
  struct sockaddr_un un;
  size_t len;

  unlink(path); /* remove old socket if exists */
  if ((socket = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
    perror("socket");
    return -1;
  }

  un.sun_family = AF_UNIX;
  strncpy(un.sun_path, path, sizeof(un.sun_path));
  
  if (bind(socket, (struct sockaddr *) &un, sizeof(un)) == -1) {
    perror("bind");
    return -1;
  }
  if (listen(socket, 1) == -1) {
    perror("listen");
    return -1;
  }
}

int vhost_user_send(int socket, struct vhost_user_msg *msg) {
  int ret;

  struct msghdr msgh;
  struct iovec iov[1];

  size_t fd_size = msg->nfds * sizeof(int);
  char control[CMSG_SPACE(fd_size)];
  struct cmsghdr *cmsg;

  memset(&msgh, 0, sizeof(msgh));
  memset(control, 0, sizeof(control));

  iov[0].iov_base = (void *)msg;
  iov[0].iov_len = sizeof(struct vhost_user_msg);

  msgh.msg_iov = iov;
  msgh.msg_iovlen = 1;

  if (msg->nfds) {
    msgh.msg_conrol = control;
    msgh.msg_controllen = sizeof(control);

    cmsg = CMSG_FIRSTHDR(&msgh);

    cmsg->cmsg_len = CMSG_LEN(fd_size);
    cmsg->cmsg_level = SOL_SOCKET;
    cmsg->cmsg_type = SCM_RIGHTS;
    memcpy(CMSG_DATA(cmsg), msg->fds, fd_size);
  } else {
    msgh.msg_control = 0;
    msgh.msg_controllen = 0;
  }

  do {
    ret = sendmsg(fd, &msgh, 0);
  } while (ret < 0 && errno == EINTR);

  if (ret < 0) {
    perror("sendmsg");
  }

  return ret;
}

int vhost_user_receive(int socket, struct vhost_user_msg *msg) {
  struct msghdr msgh;
  struct iovec iov[1];
  int ret;

  int fd_size = sizeof(msg->fds);
  char control[CMSG_SPACE(fd_size)];
  struct cmsghdr *cmsg;

  memset(&msgh, 0, sizeof(msgh));
  memset(control, 0, sizeof(control));
  msg->nfds = 0;

  iov[0].iov_base = (void *) msg;
  iov[0].iov_len = sizeof(*msg);

  msgh.msg_iov = iov;
  msgh.msg_iovlen = 1;
  msgh.msg_control = control;
  msgh.msg_controllen = sizeof(control);

  ret = recvmsg(fd, &msgh, 0);
  if (ret > 0) {
    if (msgh.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) {
      ret = -1;
    } else {
      // Copy file descriptors
      cmsg = CMSG_FIRSTHDR(&msgh);
      if (cmsg && cmsg->cmsg_len > 0&&
          cmsg->cmsg_level == SOL_SOCKET &&
          cmsg->cmsg_type == SCM_RIGHTS) {
        if (fd_size >= cmsg->cmsg_len - CMSG_LEN(0)) {
          fd_size = cmsg->cmsg_len - CMSG_LEN(0);
          memcpy(&msg->fds, CMSG_DATA(cmsg), fd_size);
          msg->nfds = fd_size / sizeof(int);
        }
      }
    }
  }

  if (ret < 0) {
    perror("recvmsg");
  }

  return ret;
}

void* map_guest_memory(int fd, int size) {
  void *ptr = mmap(0, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  return ptr == MAP_FAILED ? 0 : ptr;
}

int unmap_guest_memory(void *ptr, int size) {
  munmap(ptr, size);
}

int sync_shm(void *ptr, size_t size) {
  return msync(ptr, size, MS_SYNC | MS_INVALIDATE);
}
