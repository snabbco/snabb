
local counter = require('lib.ipc.shmem.counter')
local base = nil

local stats = {}

function stats.new()
   local cntr = counter:new{filename="free_packet_stats.shmem"}
   cntr:register('frees', 0)
   cntr:register('freebytes', 0)
   cntr:register('freebits', 0)
   cntr:register('lastfrees', 0)
   cntr:register('lastfreebytes', 0)
   cntr:register('lastfreebits', 0)
   cntr:register('reportedfrees', 0)
   cntr:register('reportedfreebytes', 0)
   cntr:register('reportedfreebits', 0)
   base = cntr:base()
end


function stats.attach()
   local cntr = counter:attach{filename="free_packet_stats.shmem"}
   base = cntr:base()
end


function stats.add(p)
   base[0] = base[0] + 1                                        -- frees
   base[1] = base[1] + p.length                                 -- freebytes
   -- Calculate bits of physical capacity required for packet on 10GbE
   -- Account for minimum data size and overhead of CRC and inter-packet gap
   base[2] = base[2] + (math.max(p.length, 46) + 4 + 5) * 8     -- freebits
end


function stats.breathe()
   local newfrees = base[0] - base[3]       -- frees - lastfrees
   for i = 0, 3 do
      base[i+3] = base[i]
   end
   return newfrees
end


function stats.report()
   local newfrees = base[0] - base[6]
   local newbytes = base[1] - base[7]
   local newbits  = base[2] - base[8]
   for i = 0, 3 do
      base[i+6] = base[i]
   end
   return newfrees, newbytes, newbits
end


return stats
