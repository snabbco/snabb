#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <stdint.h>
#include <strings.h>
#include <stdio.h>
#include <errno.h>
#include "core/packet.h"

int send_packet(int fd, struct packet *p) {
  struct msghdr msg;
  struct iovec iovecs[PACKET_IOVEC_MAX];
  int i, n = p->niovecs;

  bzero(&msg, sizeof(msg));
  for (i=0; i < n; i++) {
    struct packet_iovec  *piov = &p->iovecs[i];
    struct iovec *iov = &iovecs[i];

    iov->iov_base = piov->buffer->pointer + piov->offset;
    iov->iov_len  = piov->length;
  }
  msg.msg_iov = &iovecs[0];
  msg.msg_iovlen = n;

  if (sendmsg(fd, &msg, 0) == -1) {
    perror("sendmsg");
    return(-1);
  }
  return(0);
}

int receive_packet(int fd, struct packet *p) {
  struct msghdr msg;
  struct iovec iovecs[p->niovecs];
  int i;
  ssize_t s, len;

  bzero(&msg, sizeof(msg));
  for (i=0; i<p->niovecs; i++) {
    iovecs[i].iov_base = p->iovecs[i].buffer->pointer;
    iovecs[i].iov_len  = p->iovecs[i].buffer->size;
  }
  msg.msg_iov = iovecs;
  msg.msg_iovlen = p->niovecs;
  if ((s = recvmsg(fd, &msg, 0)) == -1) {
    perror("recvmsg");
    return(-1);
  }
  if (msg.msg_flags && MSG_TRUNC) {
    printf("truncated\n");
    return(-1);
  }
  len = s;
  for (i=0; i<p->niovecs; i++) {
    ssize_t iov_len = msg.msg_iov[i].iov_len;
    if (len > iov_len) {
      p->iovecs[i].length = iov_len;
      len -= iov_len;
    } else {
      p->iovecs[i].length = len;
    }
  }
  p->length = s;
  return(s);
}

int msg_size(int fd) {
  int size;
  if (ioctl(fd, FIONREAD, &size) == -1) {
    perror("get message size");
    return(-1);
  }
  return(size);
}

int can_receive(int fd) {
  fd_set fds;
  struct timeval tv = { .tv_sec = 0, .tv_usec = 0 };
  int result;

  FD_ZERO(&fds);
  FD_SET(fd, &fds);
  if ((result = select(fd+1, &fds, NULL, NULL, &tv)) == -1) {
    perror("select");
    return(-1);
  }
  return(result);
}

int can_transmit(int fd) {
  fd_set fds;
  struct timeval tv = { .tv_sec = 0, .tv_usec = 0 };
  int result;

  FD_ZERO(&fds);
  FD_SET(fd, &fds);
  if ((result = select(fd+1, NULL, &fds, NULL, &tv)) == -1) {
    perror("select");
    return(-1);
  }
  return(result);
}
