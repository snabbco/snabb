/* Copyright 2012 Snabb GmbH. See the file COPYING for license details. */

#include <stdio.h>
#include <stdint.h>
#include <sys/mman.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include "snabb.h"
#include <net/snabb-shm-dev.h>

void test ()
{
  printf("test()\n");
}

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

