local ffi = require("ffi")

-- Unsinking is what happens when a "sunk" allocation needs to be
-- performed at trace exit time. The JIT has optimized away the
-- allocation within the trace machine code but when we exit back to
-- the interpeter the fully allocated value can be required.
--
-- (Strictly speaking unsinking is what happens when a sunk allocation
-- is referenced by the snapshot of a taken trace exit and the Lua
-- stack needs to be reconstructed for the interpreter to use.)

local array = ffi.new("struct { int x; } [1]")

do --- unsink constant pointer

   -- This test forces the VM to unsink a pointer that was constructed
   -- from a constant. The IR will include a 'cnewi' instruction to
   -- allocate an FFI pointer object, the pointer value will be an IR
   -- constant, the allocation will be sunk, and the allocation will
   -- at some point be "unsunk" due to a reference in the snapshot for
   -- a taken exit.

   -- Note: JIT will recognize <array> as a "singleton" and allow its
   -- address to be inlined ("constified") instead of looking up the
   -- upvalue at runtime.

   local function fn (i)
      local struct = array[0]   -- Load pointer that the JIT will constify.
      if i == 1000 then end     -- Force trace exit when i==1000.
      struct.x = 0              -- Ensure that 'struct' is live after exit.
   end

   -- Loop over the function to make it compile and take a trace exit
   -- during the final iteration.
   for i = 1, 1000 do
      fn(i)
   end
end

