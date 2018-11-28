module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C

tunnel = {
   config = {
      vcs = { default = {} },
      logger = { default = nil },
   }
}

function tunnel:push ()
   local sin = self.input.south
   local sout = self.output.south

   for _, vc in ipairs(self.vcs) do
      local vc_out = self.output[vc.link_name]
      local vc_in = self.input[vc.link_name]

      for _ = 1, link.nreadable(sin) do
         local p = link.receive(sin)
         if C.memcmp(p.data, vc.header_in_ptr, self.header_size) == 0 then
            link.transmit(vc_out, packet.shiftleft(p, self.header_size))
         else
            link.transmit(sin, p)
         end
      end

      for _ = 1, link.nreadable(vc_in) do
         local p = link.receive(vc_in)
         p = packet.prepend(p, vc.header_out_ptr, self.header_size)
         link.transmit(sout, p)
      end
   end

   for _ = 1, link.nreadable(sin) do
      local p = link.receive(sin)
      self:handle_unknown_header_fn(p)
      packet.free(p)
   end
end
