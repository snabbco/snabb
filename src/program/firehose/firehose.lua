-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local lib = require("core.lib")

local long_opts = {
   help             = "h",
   example          = "e",
   ["print-header"] = "H",
   time             = "t",
   input            = "i",
   ["ring-size"]    = "r",
}

function fatal (reason)
   print(reason)
   os.exit(1)
end

function run (args)
   local usage = require("program.firehose.README_inc")
   local header = require("program.firehose.firehose_h_inc")
   local example = require("program.firehose.example_inc")

   local opt = {}
   local time = nil
   local pciaddresses = {}
   local ring_size = 2048
   function opt.h (arg) print(usage)  main.exit(0) end
   function opt.H (arg) print(header) main.exit(0) end
   function opt.e (arg) print(example) main.exit(0) end
   function opt.t (arg)
      time = tonumber(arg)
      if type(time) ~= 'number' then fatal("bad time value: " .. arg) end
   end
   function opt.i (arg)
      table.insert(pciaddresses, arg)
   end
   function opt.r (arg)
      ring_size = tonumber(arg)
   end
   args = lib.dogetopt(args, opt, "hHet:i:r:", long_opts)
   if #pciaddresses == 0 then
      fatal("Usage error: no input sources given (-i). Use --help for usage.")
   end

   local sofile = args[1]

   -- Load shared object
   print("Loading shared object: "..sofile)
   local ffi = require("ffi")
   local C = ffi.C
   local so = ffi.load(sofile)
   ffi.cdef[[
void firehose_start();
void firehose_stop();
int firehose_callback_v1(const char *pciaddr, char **packets, void *rxring,
                         int ring_size, int index);
]]

   -- Array where we store a function for each NIC that will process the traffic.
   local run_functions = {}

   for _,pciaddr in ipairs(pciaddresses) do

      -- Initialize a device driver
      print("Initializing NIC: "..pciaddr)

      local pci = require("lib.hardware.pci")
      pci.unbind_device_from_linux(pciaddr) -- make kernel/ixgbe release this device

      local intel10g = require("apps.intel.intel10g")
      -- Maximum buffers to avoid packet drops
      intel10g.ring_buffer_size(ring_size)
      local nic = intel10g.new_sf({pciaddr=pciaddr})
      nic:open()

      -- Traffic processing
      --
      -- We are using a special-purpose receive method designed for fast
      -- packet capture:
      --
      --   Statically allocate all packet buffers.
      --
      --   Statically initialize the hardware RX descriptor ring to point to
      --   the preallocated packets.
      --
      --   Have the C callback loop directly over the RX ring to process the
      --   packets that are ready.
      --
      -- This means that no work is done to allocate and free buffers or to
      -- write new descriptors to the RX ring. This is expected to have
      -- extremely low overhead to recieve each packet.

      -- Set NIC to "legacy" descriptor format. In this mode the NIC "write
      -- back" does not overwrite the address stored in the descriptor and
      -- so this can be reused. See 82599 datasheet section 7.1.5.
      nic.r.SRRCTL(10 + bit.lshift(1, 28))
      -- Array of packet data buffers. This will be passed to C.
      local packets = ffi.new("char*[?]", ring_size)
      for i = 0, ring_size-1 do
         -- Statically allocate a packet and put the address in the array
         local p = packet.allocate()
         packets[i] = p.data
         -- Statically allocate the matching hardware receive descriptor
         nic.rxdesc[i].data.address = memory.virtual_to_physical(p.data)
         nic.rxdesc[i].data.dd = 0
      end
      nic.r.RDT(ring_size-1)

      local index = 0 -- ring index of next packet
      local rxring = nic.rxdesc
      local run = function ()
         index = so.firehose_callback_v1(pciaddr, packets, rxring, ring_size, index)
         nic.r.RDT(index==0 and ring_size or index-1)
      end
      table.insert(run_functions, run)
   end

   print("Initializing callback library")
   so.firehose_start()

   -- Process traffic in infinite loop
   print("Processing traffic...")

   local deadline = time and (C.get_monotonic_time() + time)
   while true do
      for i = 1, 10000 do
         for i = 1, #run_functions do
            -- Run the traffic processing function for each NIC.
            run_functions[i]()
         end
      end
      if deadline and (C.get_monotonic_time() > deadline) then
         so.firehose_stop()
         break
      end
   end

end

