/* Copyright 2012 Snabb GmbH. See the file COPYING for license details. */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <net/if.h>
#include <linux/if_tun.h>

#include "snabb.h"
#include <net/snabb-shm-dev.h>

struct snabb_shm_dev *open_shm(const char *path)
{
    int fd;
    struct snabb_shm_dev *dev;
    assert( (fd = open(path, O_RDWR)) >= 0 );
    dev = (struct snabb_shm_dev *)
        mmap(NULL, sizeof(struct snabb_shm_dev),
             PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
    assert( dev != MAP_FAILED );
    assert( dev->magic == 0x57ABB000 );
    return dev;
}

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

