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
  if (write(fd, &p->data, p->length) == -1) {
    perror("sendmsg");
    return(-1);
  }
  return(0);
}

int receive_packet(int fd, struct packet *p) {
  ssize_t s;

  s = read(fd, &p->data, sizeof(p->data));
  if (s == -1) {
    perror("read");
    return(-1);
  }
  p->length = s;
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
