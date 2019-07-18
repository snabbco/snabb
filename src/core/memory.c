// memory.c - supporting code for DMA memory management
// Use of this source code is governed by the Apache 2.0 license; see COPYING.

// This file implements a SIGSEGV handler that traps access to DMA
// memory that is available to the Snabb process but not yet mapped.
// These accesses are transparently supported by mapping the required
// memory "just in time."
//
// The overall effect is that each Snabb process in a group can
// transparently access the DMA memory allocated by other processes.
// DMA pointers in each process are also valid in all other processes
// within the same group.
//
// Note that every process maps DMA memory to the same address i.e.
// the physical address of the memory with some tag bits added.

#include <assert.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/ucontext.h>
#include <unistd.h>

// See memory.lua for pointer tagging scheme.
#define TAG 0x500000000000ULL
#define PATH_MAX 256

static uint64_t page_mask;
static char path_template[PATH_MAX];

// Counter for the number of times a page has been mapped on-demand by
// the SIGSEGV handler.
int memory_demand_mappings;

static void memory_sigsegv_handler(int sig, siginfo_t *si, void *uc);

// Install signal handler
static void set_sigsegv_handler()
{
  struct sigaction sa;
  sa.sa_flags = SA_SIGINFO;
  sigemptyset(&sa.sa_mask);
  sa.sa_sigaction = memory_sigsegv_handler;
  assert(sigaction(SIGSEGV, &sa, NULL) != -1);
}

static void memory_sigsegv_handler(int sig, siginfo_t *si, void *uc)
{
  int fd = -1;
  struct stat st;
  char path[PATH_MAX];
  uint64_t address = (uint64_t)si->si_addr;
  uint64_t page = address & ~TAG & page_mask;
  // Disable this handler to avoid potential recursive signals.
  signal(SIGSEGV, SIG_DFL);
  fflush(stdout);
  // Check that this is a DMA memory address
  if ((address & TAG) != TAG) {
    goto punt;
  }
  snprintf(path, PATH_MAX, path_template, page);
  // Check that the memory is accessible to this process
  if ((fd = open(path, O_RDWR)) == -1) {
    goto punt;
  }
  if (fstat(fd, &st) == -1) {
    goto punt;
  }
  // Map the memory at the expected address
  if (mmap((void *)(page | TAG), st.st_size, PROT_READ|PROT_WRITE,
           MAP_SHARED|MAP_FIXED, fd, 0) == MAP_FAILED) {
    goto punt;
  }
  close(fd);
  memory_demand_mappings++;
  // Re-enable the handler for next time
  set_sigsegv_handler();
  return;
 punt:
  // Log useful details, including instruction and stack pointers.
  // See https://stackoverflow.com/a/7102867
  fprintf(stderr, "snabb[%d]: segfault at %p ip %p sp %p code %d errno %d\n",
          getpid(),
          si->si_addr,
          (void *)((ucontext_t *)uc)->uc_mcontext.gregs[REG_RIP],
          (void *)((ucontext_t *)uc)->uc_mcontext.gregs[REG_RSP],
          si->si_code,
          si->si_errno);
  fflush(stderr);
  // Fall back to the default SEGV behavior by resending the signal
  // now that the handler is disabled.
  // See https://www.cons.org/cracauer/sigint.html
  kill(getpid(), SIGSEGV);
}

// Setup a SIGSEGV handler to map DMA memory on demand.
void memory_sigsegv_setup(int huge_page_size, const char *path)
{
  // Save parameters
  page_mask = ~(uint64_t)(huge_page_size - 1);
  assert(strlen(path) < PATH_MAX);
  strncpy(path_template, path, PATH_MAX);
  memory_demand_mappings = 0;
  set_sigsegv_handler();
}

