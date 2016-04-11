module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
Delayed_start = { }

--[[
An app that delays packet forwarding for a configurable period of time.
Useful when feeding pcaps into a physical nic. The delay lets the peer
NIC completely initialize before sending packets so none are dropped.
]]
function Delayed_start:new(delay)
   return setmetatable({ delay = delay }, { __index = Delayed_start})
end

function Delayed_start:push()
   if self.delay then
      C.usleep(self.delay)
      self.delay = nil
   end
   for _ = 1, link.nreadable(self.input.input) do
      link.transmit(self.output.output, link.receive(self.input.input))
   end
end
