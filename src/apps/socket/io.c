#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#include <stdint.h>
#include <strings.h>
#include <stdio.h>
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

int receive_packet(int fd, struct buffer *b) {
  struct msghdr msg;
  struct iovec iovec;
  ssize_t s;

  bzero(&msg, sizeof(msg));
  iovec.iov_base = b->pointer;
  iovec.iov_len  = b->size;
  msg.msg_iov = &iovec;
  msg.msg_iovlen = 1;
  if ((s = recvmsg(fd, &msg, 0)) == -1) {
    perror("recvmsg");
    return(-1);
  }
  return(s);
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
