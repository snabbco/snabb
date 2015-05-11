require ('apps.basic.basic')

local size = size or 60
local pkt = packet.from_pointer (ffi.new("char[?]", size), size)

function pull()
   for _, o in ipairs(outputi) do
      for i = 1, link.nwritable(o) do
         link.transmit(o, packet.clone(pkt))
      end
   end
end


function stop()
   packet.free(pkt)
end
