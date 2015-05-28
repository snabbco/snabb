-- The top subclass of lib.ipc.shmem.shmem manages a shared memory
-- mapping dedicated to core engine stats used by `snabb top'. It
-- contains counters for engine "frees", "bytes" freed, and "breaths" as
-- well an array of I/O metrics for each active link.
--
-- Top can store up to `max_links' links, each link consisting of: the
-- link's name and rxpackets, txpackets, rxbytes, txbytes and txdrop
-- counters.
module(...,package.seeall)

local ffi = require("ffi")
local shmem = require("lib.ipc.shmem.shmem")

local link_name_max_length = 255
local max_links = 255

local top = subClass(shmem)
top._name = "Core engine stats"
top._namespace = "Top"
top._version = 1

function top:new (location)
   local o = top:superClass().new(self, location_or_default(location))
   register_top(o)
   return o
end

function top:attach (location)
   local o = top:superClass().attach(self, location_or_default(location))
   register_top(o)
   return o
end

function top:set_n_links (n)
   assert(n <= (max_links+1), "n is > than max_links+1.")
   self:ptr("links")[0].n = n
end

function top:n_links ()
   return self:ptr("links")[0].n
end

function top:set_link_name (index, name)
   check_link_index(self, index)
   local link = self:ptr("links")[0].links[index]
   ffi.copy(link.name, name, #name)
   link.name_length = #name
end

function top:set_link
   (index, rxpackets, txpackets, rxbytes, txbytes, txdrop)
   check_link_index(self, index)
   local link = self:ptr("links")[0].links[index]
   link.rxpackets, link.txpackets, link.rxbytes, link.txbytes, link.txdrop =
      rxpackets, txpackets, rxbytes, txbytes, txdrop
end

function top:get_link (index)
   check_link_index(self, index)
   local link = self:ptr("links")[0].links[index]
   local name = ffi.string(link.name, link.name_length)
   return { name = name,
            rxpackets = link.rxpackets,
            txpackets = link.txpackets,
            rxbytes = link.rxbytes,
            txbytes = link.txbytes,
            txdrop = link.txdrop }
end


-- Helper functions.

function location_or_default (location)
   return location or { filename = "snabb-top", directory = "/tmp" }
end

function register_top (stats)
   -- Expose frees, bytes and breaths counters.
   local counter_t = ffi.typeof("uint64_t")
   stats:register("frees", counter_t)
   stats:register("bytes", counter_t)
   stats:register("breaths", counter_t)

   -- Expose link stats.
   ffi.cdef(
      [[typedef struct { uint8_t name_length; char name[$];
                        $ rxpackets, txpackets, rxbytes, txbytes, txdrop;
      } stat_link]],
      link_name_max_length, counter_t
   )
   local link_t  = ffi.typeof("stat_link")

   ffi.cdef("typedef struct { uint8_t n; $ links[$]; } stat_links",
            link_t, max_links)
   local links_t = ffi.typeof("stat_links")

   stats:register("links", links_t)

   return stats
end

function check_link_index (top, index)
   assert(index < top:n_links(), "link index is not < n_links.")
end

return top
