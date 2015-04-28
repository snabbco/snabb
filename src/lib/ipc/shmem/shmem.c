#include <sys/mman.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdbool.h>

bool shmem_unmap(void *mem, size_t size) {
  if (munmap(mem, size) == -1) {
    perror("munmap");
    return(false);
  }
  return(true);
}

// Note: the io.* file handle passed to us is converted to a Unix
// filehandle (FILE *) by LuaJIT
char *shmem_grow(void *fh, void *old_mem, size_t old_size, size_t new_size) {
  int fd;
  void *mem;

  if (old_mem != NULL) {
    if (shmem_unmap(old_mem, old_size) == false) {
      return(NULL);
    }
  }
  fd = fileno(fh);
  if (ftruncate(fd, new_size) == -1) {
    perror("ftruncate");
    return(NULL);
  }
  if ((mem = mmap(old_mem, new_size, PROT_READ|PROT_WRITE, MAP_SHARED,
		  fd, 0)) == MAP_FAILED) {
    perror("mmap");
    return(NULL);
  }
  return((char *)mem);
}

char *shmem_attach(void *fh, size_t length) {
  int fd;
  void *mem;

  fd = fileno(fh);
  if ((mem = mmap(NULL, length, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0)) == MAP_FAILED) {
    perror("mmap");
    return(NULL);
  }
  return((char *)mem);
}
