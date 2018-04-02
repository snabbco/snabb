-- This app is a multiplexer/demultiplexer based on the IPv6 source
-- and/or destination address of a packet.  It has a well-known port
-- called "south" that connects to the network and carries the
-- multiplexed traffic.
--
-- The app is created with a list of mappings of port names to IPv6
-- source and/or destination addresses.  A BPF filter that matches the
-- given address(es) is created for each port.
--
-- The push() method first processes all packets coming in from the
-- south port and applies the filters in turn.  When a match is found,
-- the packet is transmitted on the associated port and no more
-- filters are processed.  This implements the de-multiplexing of
-- incoming packets to specific upstream apps.
--
-- The push() method then visits each upstream port in turn and
-- multiplexes all queued packets onto the south port.

module(..., package.seeall)
local ffi = require("ffi")
local ipv6 = require("lib.protocol.ipv6")
local filter = require("lib.pcap.filter")

dispatch = subClass(nil)
dispatch._name = "IPv6 dispatcher"

-- config: table with mappings of link names to tuples of IPv6 source
-- and/or destination addresses.
-- config = { link1 = { source = source_addr, destination = destination_addr },
--            ... }
function dispatch:new (config)
   assert(config, "missing configuration")
   local o = dispatch:superClass().new(self)
   o._targets = {}
   for link, address in pairs(config) do
      assert(type(address) == 'table' and (address.source or address.destination),
             "incomplete configuration of dispatcher "..link)
      local match = {}
      if address.source then
         table.insert(match, "src host "..ipv6:ntop(address.source))
      end
      if address.destination then
         table.insert(match, "dst host "..ipv6:ntop(address.destination))
      end
      local program = table.concat(match, ' and ')
      local filter, errmsg = filter:new(program)
      assert(filter, errmsg and ffi.string(errmsg))
      print("Adding dispatcher for link "..link.." with BPF "..program)
      table.insert(o._targets, { filter = filter, link = link })
   end

   -- Caches for for various cdata pointer objects to avoid boxing in
   -- the push() loop
   o._cache = {
      p = ffi.new("struct packet *[1]"),
   }
   return o
end

local empty, full, receive, transmit = link.empty, link.full, link.receive, link.transmit
function dispatch:push()
   local output = self.output
   local targets = self._targets
   local cache = self._cache
   local l_in = self.input.south
   while not empty(l_in) do
      local p = cache.p
      p[0] = receive(l_in)

      -- De-multiplex incoming packets to PWs based on the source and
      -- destination IPv6 addresses.
      local free = true
      local i = 1
      while targets[i] do
         local t = targets[i]
         if t.filter:match(p[0].data, p[0].length) then
            transmit(output[t.link], p[0])
            free = false
            break
         end
         i = i+1
      end
      if free then packet.free(p[0]) end
   end

   -- Multiplex the packets from all PWs onto the
   -- south link.
   local l_out = output.south
   local i = 1
   while targets[i] do
      local t = targets[i]
      local l_in = self.input[t.link]
      while not empty(l_in) and not full(l_out) do
         transmit(l_out, receive(l_in))
      end
      i = i+1
   end
end
