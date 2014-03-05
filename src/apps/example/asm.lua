module(...,package.seeall)

local config = require("core.config")
local app = require("core.app")
local basic_apps = require("apps.basic.basic_apps")
local ffi = require("ffi")
local C = ffi.C

ffi.cdef[[
      extern int asm_status;
      extern struct link *asm_link_in;
      extern struct link *asm_link_out;
      void* asm_make_push();
]]

Asm = {}

function Asm:new ()
   if not Asm.push_machine_code then
      Asm.push_machine_code = ffi.cast("void*(*)()", C.asm_make_push())
   end
   return Asm
end

function Asm:pull ()
   print("asm:pull()")
end

function Asm:push ()
   print("asm:push()")
   if self.output.tx then C.asm_link_out = self.output.tx end
   print("x")
   if self.input.rx  then C.asm_link_in  = self.input.rx  end
   -- Deep breath... into the machine code!
   print("machine code...")
   print("status before: " .. bit.tohex(C.asm_status))
   self.push_machine_code()
   print("status after:  " .. bit.tohex(C.asm_status))
end

function selftest ()
   print("test")
   local c = config.new()
   config.app(c, "source", basic_apps.Source)
   config.app(c, "sink",   basic_apps.Sink)
   config.app(c, "asm", Asm)
   config.link(c, "source.tx -> asm.rx")
   config.link(c, "asm.tx    -> sink.rx")
   app.configure(c)
   app.main()
end
