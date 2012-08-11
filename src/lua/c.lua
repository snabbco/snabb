-- Copyright 2012 Snabb GmbH. See the file COPYING for license details.
module(...,package.seeall)

local ffi = require("ffi")

ffi.cdef[[
      // usleep(3) - suspend execution for microsecond intervals
      int usleep(unsigned long usec);

      // memcpy(3) - copy memory area
      void memcpy(void *dest, const void *src, size_t n);

      // memset(3) - fill memory with a constant byte
      void *memset(void *s, int c, size_t n);

      // strncpy(3) - copy a string
      char *strncpy(char *dest, const char *src, size_t n);
]]

