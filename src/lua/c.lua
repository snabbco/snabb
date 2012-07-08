module(...,package.seeall)

local ffi = require("ffi")

ffi.cdef[[
      // usleep(3) - suspend execution for microsecond intervals
      int usleep(unsigned long usec);

      // memcpy(3) - copy memory area
      void memcpy(void *dest, const void *src, size_t n);
]]

