// counter.c -- C library to support counters

#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// Create the counter file at PATH with SIZE.
// Return a pointer to the mmapped contents in shared memory.
double *counter_mmap_file(const char *path, int elements, double initial_value)
{
    int i;
    int fd;
    void *ptr;
    if ((fd = open(path, O_RDWR|O_CREAT|O_TRUNC)) < 0) {
        return NULL;
    }
    for (i = 0; i < elements; i++) {
        write(fd, &initial_value, sizeof(double));
    }
    if ((ptr = mmap(NULL, elements * sizeof(double), PROT_READ|PROT_WRITE,
                    MAP_FILE|MAP_SHARED, fd, 0)) == MAP_FAILED) {
        close(fd);
        return NULL;
    }
    return (double *)ptr;
}

