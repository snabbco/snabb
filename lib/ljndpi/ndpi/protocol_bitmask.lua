#! /usr/bin/env lua
--
-- protocol_bitmask.lua
-- Copyright (C) 2016 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local ffi = require("ffi")
local bit = require("bit")
local band, bor, bnot, lshift = bit.band, bit.bor, bit.bnot, bit.lshift

---------------------------------------------------- Protocol Bitmask ------
--
-- nDPI defines the NDPI_PROTOCOL_BITMASK type as a struct which contains
-- an array of 32-bit integers. The size of the array is calculated so in
-- total it contains at least NDPI_NUM_BITS bits. For user-space code this
-- is currently defined to be 256 bits.
--
-- The following code does a similar dance to define a compatible FFI type
-- in such a way that changing NDPI_NUM_BITS here to have the same value
-- used by nDPI automatically defines the bitmask type correctly.
--
local NDPI_NUM_BITS = 256  -- Value from "ndpi_define.h"
local NDPI_BITS     = 32   -- Bit width of ndpi_ndpi_mask

-- Calculate the amount of needed integers to hold NDPI_NUM_BITS
local NUM_FDS_BITS = (NDPI_NUM_BITS + (NDPI_BITS - 1)) / NDPI_BITS

ffi.cdef(([[
   typedef struct ndpi_protocol_bitmask_struct {
      uint%d_t fds_bits[%d];
   } ndpi_protocol_bitmask_t;
]]):format(NDPI_BITS, NUM_FDS_BITS))

local bitmask_struct_size = ffi.sizeof("ndpi_protocol_bitmask_t")

------------------------------------------ Protocol Bitmask Functions ------
--
-- Note that most of the functions return the bitmask itself, which allows
-- to conveniently chain operations. This is particularly neat when using
-- the FFI metatype, e.g:
--
--   mask = meta_type():set_all():del(42):del(12)
--

local function bitmask_add(self, n)
   self.fds_bits[n / NDPI_BITS] = bor(self.fds_bits[n / NDPI_BITS],
                                      lshift(1, n % NDPI_BITS))
   return self
end

local function bitmask_del(self, n)
   self.fds_bits[n / NDPI_BITS] = band(self.fds_bits[n / NDPI_BITS],
                                       bnot(lshift(1, n % NDPI_BITS)))
   return self
end

local function bitmask_reset(self)
   ffi.fill(self, bitmask_struct_size)
   return self
end

local function bitmask_set_all(self)
   ffi.fill(self, bitmask_struct_size, 0xFF)
   return self
end

local function bitmask_set(self, other)
   ffi.copy(self, other, bitmask_struct_size)
   return self
end

local function bitmask_is_set(self, n)
   local val = lshift(1, n % NDPI_BITS)
   return band(self.fds_bits[n / NDPI_BITS], val) == val
end

return {
   -- Naming above follows "ndpi_define.h" to make it easier to correlate
   -- with the nDPI header, but the module exports friendlier names.
   NUM_BITS      = NDPI_NUM_BITS;
   BITS_PER_ITEM = NDPI_BITS;
   NUM_ITEMS     = NUM_FDS_BITS;

   -- Functions.
   bitmask_add     = bitmask_add;
   bitmask_del     = bitmask_del;
   bitmask_reset   = bitmask_reset;
   bitmask_set_all = bitmask_set_all;
   bitmask_set     = bitmask_set;
   bitmask_is_set  = bitmask_is_set;

   -- Types. The metatype allows invoking methods directly on the objects.
   base_type = base_type;
   meta_type = ffi.metatype("ndpi_protocol_bitmask_t", {
      __index = {
         add     = bitmask_add;
         del     = bitmask_del;
         reset   = bitmask_reset;
         set_all = bitmask_set_all;
         set     = bitmask_set;
         is_set  = bitmask_is_set;
      };
   });
}
