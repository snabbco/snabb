#include <fcntl.h>
#include <linux/if_tun.h>
#include <net/if.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>


/* Open a Linux TAP device and return its file descriptor, or -1 on error.

   TAP is a virtual network device where we can exchange ethernet
   frames with the host kernel.

   'name' is the name of the host network interface, e.g. 'tap0', or
   an empty string if a name should be provisioned on demand. */
int open_tap(const char *name)
{
    struct ifreq ifr;
    int fd;
    if ((fd = open("/dev/net/tun", O_RDWR | O_NONBLOCK)) < 0) {
        perror("open /dev/net/tun");
        return -1;
    }
    memset(&ifr, 0, sizeof(ifr));
    ifr.ifr_flags = IFF_TAP | IFF_NO_PI;
    strncpy(ifr.ifr_name, name, sizeof(ifr.ifr_name)-1);
    if (ioctl(fd, TUNSETIFF, (void*)&ifr) < 0) {
        perror("TUNSETIFF");
        return -1;
    }
    return fd;
}
