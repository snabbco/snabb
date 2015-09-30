-- PMU "Precise Event Based Sampling" (PEBS) support
--
-- PEBS is a hardware feature where the CPU collects its own samples
-- and writes them into memory. The samples collected by the CPU can
-- include interesting details such as the data address that is being
-- referenced when a cache miss occurs. Events can be triggered based
-- on a subset of performance events (cache misses, etc).
--
-- This module sets up PEBS and enables event logging into memory.
--
-- Refer to Intel's system programming manual (vol.3) for details:
-- http://www.intel.com/content/www/us/en/processors/architectures-software-developer-manuals.html

module(..., package.seeall)

local ffi = require("ffi")
local pmu = require("lib.pmu")

-- Data structure describing the "debug save" memory area.
-- This is supplied to the CPU with a WRMSR IA32_DS_AREA.
-- The debug save area specifies two buffers:
-- BTS (branch tracing) that we don't care about.
-- PEBS (performance events) that we do care about.
local ds_save_t = ffi.typeof[[
  struct {
    uint64_t bts_buffer_base,
	     bts_index,
	     bts_abs_max,
	     bts_int_thresh,
	     pebs_buffer_base,
	     pebs_index,
	     pebs_abs_max,
	     pebs_int_thresh,
	     pebs_counter_reset,
	     reserved;
  }
]]

-- PEBS record format. This is the record that the CPU writes into the
-- "debug save" memory area when sampling a performance event.
-- 
-- This includes some goodies: an extra-accurate Instruction Pointer
-- value, the address of a load/store, and the number of cycles of
-- latency.
local pebs_t = ffi.typeof[[
  struct {
    uint64_t eflags,
	     eip,
	     regs[16],
	     perf_global_status,
	     data_linear_address,
	     data_source_encoding,
	     latency,
	     event_ip,
             tx_abort;
  }
]]
local pebs_sz = ffi.sizeof(pebs_t)

-- Align x to an a-byte boundary using subtraction.
function backalign (x, a) return x - (x % a) end
-- Resolve "linear address". (XXX maybe not right? check Intel SPG section 3)
function linear (addr)    return memory.virtual_to_physical(addr) end

local ds_save = ffi.cast(ffi.typeof("$*", ds_save_t), memory.dma_alloc(ffi.sizeof(ds_save_t)))
local btsmem  = ffi.cast("void*",                     memory.dma_alloc(2*1024*1024))
local pebsmem = ffi.cast(ffi.typeof("$*", pebs_t),    memory.dma_alloc(2*1024*1024))
-- Create a dummy (don't care) BTS memory region
ds_save.bts_buffer_base  = memory.virtual_to_physical(ffi.cast("uint64_t", btsmem))
ds_save.bts_index        = ds_save.bts_buffer_base
ds_save.bts_abs_max      = ds_save.bts_buffer_base+1
ds_save.bts_int_thresh   = ds_save.bts_abs_max
-- Create a PEBS logging region.
ds_save.pebs_buffer_base = memory.virtual_to_physical(ffi.cast("uint64_t", pebsmem))
ds_save.pebs_index       = ds_save.pebs_buffer_base
ds_save.pebs_abs_max     = ds_save.pebs_buffer_base + backalign(2*1024*1024, pebs_sz) + 1
ds_save.pebs_int_thresh  = ds_save.pebs_abs_max + pebs_sz
ds_save.pebs_counter_reset = 100

-- 18.4.4.1
function selftest ()
   print("selftest: pmu_pebs")
   -- Enable debug store
   pmu.writemsr(0, 0x600, ffi.cast("uint64_t", memory.virtual_to_physical(ds_save)))
   -- Enable PEBS on PMC0
   pmu.writemsr(0, 0x3f1, 0xF)
   -- Do some work with profiling enabled
   pmu.profile(function () for i = 1, 100 do collectgarbage() end end,
         -- Choose an event that supports PEBS
         {'inst_retired.any_p'})
   -- Dump beginning of log
   -- If PEBS is working then this should contain some data.
   -- (Have not got it working yet...)
   print(core.lib.hexdump(ffi.string(pebsmem, 512)))
   print("selftest done")
end

