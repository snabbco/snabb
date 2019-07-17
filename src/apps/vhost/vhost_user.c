/* Use of this source code is governed by the Apache 2.0 license; see COPYING. */

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include "lib/virtio/virtio_vring.h"
#include "vhost.h"
#include "vhost_user.h"

#define MEMB_SIZE(t,m)      (sizeof(((t*)0)->m))
#define VHOST_USER_HDR_SIZE (MEMB_SIZE(struct vhost_user_msg,request) \
                            + MEMB_SIZE(struct vhost_user_msg,flags) \
                            + MEMB_SIZE(struct vhost_user_msg,size))

#define VHOST_USER_LISTEN   1

int vhost_user_connect(const char *path)
{
    int sock;
    struct sockaddr_un un;

    if ((sock = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
        perror("socket");
        return -1;
    }

    un.sun_family = AF_UNIX;
    strncpy(un.sun_path, path, sizeof(un.sun_path)-1);

    if (connect(sock, (struct sockaddr *) &un, sizeof(un)) == -1) {
        close(sock);
        return -1;
    }

    return sock;
}

int vhost_user_listen(const char *path)
{
    int sock;
    struct sockaddr_un un;

    if ((sock = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
        perror("socket");
        return -1;
    }

    un.sun_family = AF_UNIX;
    strncpy(un.sun_path, path, sizeof(un.sun_path)-1);
    unlink(un.sun_path);
    if (bind(sock, (struct sockaddr *) &un, sizeof(un)) == -1) {
        close(sock);
        return -1;
    }

    if (listen(sock, VHOST_USER_LISTEN) == -1) {
        close(sock);
        return -1;
    }
    return sock;
}

int vhost_user_accept(int sock)
{
    int newsock;
    if ((newsock = accept(sock, NULL, NULL)) == -1) {
        assert(errno == EAGAIN);
    } else {
        assert(fcntl(newsock, F_SETFL, O_NONBLOCK) == 0);
    }
    return newsock;
}

int vhost_user_send(int sock, struct vhost_user_msg *msg)
{
    int ret;

    struct msghdr msgh;
    struct iovec iov[1];

    memset(&msgh, 0, sizeof(msgh));

    iov[0].iov_base = (void *) msg;
    iov[0].iov_len = VHOST_USER_HDR_SIZE + msg->size;

    msgh.msg_iov = iov;
    msgh.msg_iovlen = 1;

    msgh.msg_control = 0;
    msgh.msg_controllen = 0;

    do {
        ret = sendmsg(sock, &msgh, 0);
    } while (ret < 0 && errno == EINTR);

    if (ret < 0) {
        perror("sendmsg");
    }

    return ret;
}

int vhost_user_receive(int sock, struct vhost_user_msg *msg, int *fds,
        int *nfds)
{
    struct msghdr msgh;
    struct iovec iov[1];
    int ret;

    int fd_size = sizeof(int) * VHOST_USER_MEMORY_MAX_NREGIONS;
    char control[CMSG_SPACE(fd_size)];
    struct cmsghdr *cmsg;

    memset(&msgh, 0, sizeof(msgh));
    memset(control, 0, sizeof(control));
    *nfds = 0;

    iov[0].iov_base = (void *) msg;
    iov[0].iov_len = VHOST_USER_HDR_SIZE;

    msgh.msg_iov = iov;
    msgh.msg_iovlen = 1;
    msgh.msg_control = control;
    msgh.msg_controllen = sizeof(control);

    do {
        ret = recvmsg(sock, &msgh, MSG_DONTWAIT | MSG_WAITALL);
    } while (ret < 0 && errno == EINTR);
    if (ret == VHOST_USER_HDR_SIZE) {
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
                    memcpy(fds, CMSG_DATA(cmsg), fd_size);
                    *nfds = fd_size / sizeof(int);
                }
            }
            if (msg->size > 0) {
                do {
                    ret = read(sock, ((char*) msg) + VHOST_USER_HDR_SIZE,
                            msg->size);
                } while (ret < 0 && errno == EINTR);
            }
        }
    }
    if (ret < 0 && errno != EAGAIN) {
        perror("recvmsg");
    }
    return ret;
}

void* vhost_user_map_guest_memory(int fd, uint64_t size)
{
    void *ptr = mmap(0, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    return ptr == MAP_FAILED ? 0 : ptr;
}

int vhost_user_unmap_guest_memory(void *ptr, uint64_t size)
{
    return munmap(ptr, size);
}

int vhost_user_sync_shm(void *ptr, size_t size)
{
    return msync(ptr, size, MS_SYNC | MS_INVALIDATE);
}
