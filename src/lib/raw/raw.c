#include <fcntl.h>
#include <net/if.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <netpacket/packet.h>
#include <net/ethernet.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* Open a raw socket and return its file descriptor, or -1 on error.

   'name' is the name of the host network interface to which the socket
   is attached, e.g. 'eth0'. */
int open_raw(const char *name)
{
    struct ifreq ifr;
    struct sockaddr_ll sll;
    int fd;
    if ((fd = socket(AF_PACKET, SOCK_RAW | SOCK_NONBLOCK, htons(ETH_P_ALL))) < 0) {
        perror("open raw socket");
        return -1;
    }
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, name, sizeof(ifr.ifr_name)-1);
    if (ioctl(fd, SIOCGIFINDEX, &ifr) < 0) {
      perror("get interface index");
      return -1;
    }
    sll.sll_family = AF_PACKET;
    sll.sll_ifindex = ifr.ifr_ifindex;
    sll.sll_protocol = htons(ETH_P_ALL);
    if (bind(fd, (struct sockaddr *)&sll, sizeof(sll)) < 0) {
      perror("bind raw socket to interface");
      return -1;
    }
    return fd;
}

/* Close a raw socket */
int close_raw(int fd)
{
    return close(fd);
}
