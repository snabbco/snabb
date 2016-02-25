/* Use of this source code is governed by the Apache 2.0 license; see COPYING. */

char *shmem_grow(void *, void *, size_t, size_t);
char *shmem_attach(void *, size_t);
bool shmem_unmap(void *, size_t);
