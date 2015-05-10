-- sprayer: app that drops every second packet
--
--         +---------+
--         |         |
-- input-->+ sprayer +-->output
--         |         |
--         +---------+

local snabb = require("snabb1") -- Use API version 1

-- Return alternating true, false, true, false, ...
local toggleflag = false
local function toggle ()
   toggle = not toggle
   return toggle
end
   
-- Run the sprayer app forwarding logic.
function push ()
   local input = inputs.input
   local output = outputs.output
   while not input:link_is_empty() do
      local packet = input:link_receive()
      if toggle() then
         -- Forward the packet
         output:link_transmit(packet)
      else
         -- Drop the packet
         packet:packet_free()
      end
   end
end

