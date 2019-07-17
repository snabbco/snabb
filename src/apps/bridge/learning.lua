-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- This class derives from lib.bridge.base and implements a "learning
-- bridge" using a MAC address table provided by apps.bridge.mac_table
-- to store the set of source addresses of packets arriving on all
-- ports.

-- When a packet is received on a port, the MAC source address is
-- stored in the table along with the handle of the port and the
-- handle of the split-horizon group to which the port belongs.
--
-- The decision of where to forward a packet is made by looking up the
-- destination MAC address in the table.  If there is a match, there
-- are two possible outcomes:
--
--   1. If the ingress and egress ports belong to the same
--      split-horizon group or the egress port is the same as the
--      ingress port, the packet is discarded.
--
--   2. Otherwise, the packet is forwarded to the egress port.  This
--      is referred to as "unicast forwarding".
--
-- If there is no match, the packet is flooded to all egress ports
-- that are not part of the same split-horizon group, except the
-- ingress port.  This is referred to as "flooding forwarding".
--
-- Multicast packets don't receive special treatment to avoid an
-- additional branch in the forwarding loop.  Such packets are
-- implicitely flooded because the lookup in the MAC address table
-- will always fail.
--
-- Expiration of learned MAC addresses is performed by the mac_table
-- module.
--
-- Configuration variables (via the "config" table in the generic
-- configuration of the base class):
--
--   mac_table
--
--     If specified, must be a table which is passed on unchanged to
--     the constructor of the mac_table class.  It can be used to
--     override the default settings of the MAC table used by the
--     bridge.
--
-- Notes on performance and implementation choices:
--
-- The different forwarding decisions depending on the results of the
-- MAC table lookups as described above creates multiple code paths
-- that need to be compiled efficiently.  If all of them were
-- implemented in a single loop, the compiler would only be able to
-- optimize (at most) one of them and generate much less optimized
-- code for all other cases.  The push() loop of the bridge uses two
-- techniques to overcome this problem.
--
-- The first technique is to "factorize" the code pertaining to each
-- of the use cases into separate loops, which are branch-free by
-- themselves.  This is achieved by classifying the incoming packets
-- into one of the forwarding categories (unicast, flooding, discard)
-- in the loop that reads the packets from the ingress ports.
--
-- After this loop has terminated, separate loops over each forwarding
-- table apply a single forwarding paradigm to all packets in the same
-- category.  Each loop is branch-free and can be compiled
-- efficiently.
--
-- It is obvious that the first loop, which categorizes the packets,
-- cannot be written in a branch-free manner (categorization implies
-- conditions and, hence, branches of some kind).  As a consequence,
-- this loop is very hard to get compiled efficiently for all cases.
-- This is where the second technique comes in.  It basically hides
-- the branchy code from the compiler by moving it into a C function.
-- This is all done inside the mac_table module, which also provides
-- more documentation on this issue.

module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local packet = require("core.packet")
local link = require("core.link")
local bridge_base = require("apps.bridge.base").bridge
local mac_table = require("apps.bridge.mac_table")
require("apps.bridge.learning_h")
local ethernet = require("lib.protocol.ethernet")
local logger = require("lib.logger")

local empty, receive, transmit = link.empty, link.receive, link.transmit
local clone = packet.clone

bridge = subClass(bridge_base)
bridge._name = "learning bridge"

-- ctype for a packet forwarding table
local pft_t = ffi.typeof([[
  struct {
    uint16_t length;
    pft_entry_t entries[?];
  }]])
-- ctype for a list of port handles
local port_list_t = ffi.typeof([[
  struct {
    uint16_t length;
    handle_t ports[?];
  }]])


-- Allocate packet forwarding tables (pft):
--
--   ucast Used for forwarding to a known destination MAC address.
--         A port list of length 1 is allocated for every slot in
--         this pft.
--
--   flood Used for flooding when the destination MAC address is
--         unkown.  No port lists are allocated for this pft.  The
--         mac_table:lookup_pft() method will insert a pointer to
--         the pre-allocated flooding port list associated with the
--         ingress port of the packet.
--
--   discard Used to discard packets when a destination MAC address
--           is kown but belongs to the same split-horizon group as
--           the ingress port of the packet or the egress port
--           coincides with the ingress port.
--
-- The initial size of each table is 256.  If the total number of
-- inbound packets processed by a call to push() exceeds this number,
-- all tables are re-allocated by adding the initial size to its
-- current size (linear growth).
local initial_pft_size = 256
local pft_spec = { ucast = true, flood = false, discard = false }
local function alloc_pft (self, size)
   local size = size or initial_pft_size
   local pft = { anchor = {} }
   local i = 0
   for type, alloc_pl in pairs(pft_spec) do
      pft[type] = ffi.new(pft_t, size)
      if alloc_pl then
         for i = 0, size-1 do
            -- Allocate a "unicast" port list and anchor it to prevent
            -- it from being garbage-collected.
            table.insert(pft.anchor, port_list_t(1))
            local pl = pft.anchor[#pft.anchor]
            -- C.lookup_pft() depends on this
            pl.length = 1
            pft[type].entries[i].plist = ffi.cast("port_list_t*", pl)
         end
      end
      self._pft_C[i] = ffi.cast("pft_t*", pft[type])
      i = i+1
   end
   self._pft = pft
   self._pft_size = size
end

function bridge:new (arg)
   local o = bridge:superClass().new(self, arg)
   o._mac_table = mac_table:new(o._conf.config.mac_table)

   -- Note: the indices of arrays accessed via port handles start at
   -- 1.  All other arrays start at 0.

   -- cdata version of the port-to-group mapping.
   o._p2group = ffi.new("handle_t[?]", #o._ports+1)
   for i = 1, #o._ports do
      o._p2group[i] = o._ports[i].group
   end

   -- cdata version of egress port lists used for flooding.
   local flood_pl = { anchor = {} }
   for sp, dst in ipairs(o._dst_ports) do
      local pl = port_list_t(#dst)
      pl.length = #dst
      for i = 1, #dst do
         pl.ports[i-1] = dst[i]
      end
      table.insert(flood_pl.anchor, pl)
      flood_pl[sp] = ffi.cast("port_list_t*", pl)
   end
   o._flood_pl = flood_pl
   o._pft_C = ffi.new("pft_t *[3]")
   alloc_pft(o)
   -- Box to store a pointer to a MAC address in memory
   o._mac = ffi.new("uint8_t *[1]")
   o._logger = logger.new({ module = "bridge" })
   return o
end

function bridge:push()
   local ports = self._ports
   local mac_table = self._mac_table
   local pft = self._pft
   local pft_size = self._pft_size
   pft.ucast.length = 0
   pft.flood.length = 0
   pft.discard.length = 0
   local ip = 1   -- ingress port
   local packets = 0
   while ports[ip] do
      local ig = self._p2group[ip] -- ingress split-horizon group
      local l_in = ports[ip].l_in
      while not empty(l_in) do
         local p = receive(l_in)
         packets = packets + 1
         -- Lookup the destination MAC address and associate the
         -- packet with one of the packet forwarding tables according
         -- to the result.
         local mac = self._mac
         mac[0] = p.data
         mac_table:lookup_pft(mac, ip, ig, p, self._pft_C, self._flood_pl[ip])
         -- Associate the source MAC address with the ingress port and
         -- group.  Multicast addresses are forbidden to occur as
         -- source address on the wire, but we check anyway to be sure
         -- that we don't store them by accident.
         mac[0] = mac[0] + 6
         if not ethernet:is_mcast(mac[0]) then
            mac_table:insert(mac, ip, ig)
         end
         if packets >= pft_size then
            -- Dynamically increase the size of all forwarding tables
            -- in a linear fashion.
            local new_size = self._pft_size + initial_pft_size
            if self._logger:can_log() then
               self._logger:log("packet forwarding table overflow, "
                                   .."increasing size from "
                                   ..self._pft_size.." to "
                                   ..new_size.." slots")
            end
            alloc_pft(self, new_size)
            goto BREAK
         end
      end
      ip = ip + 1
   end
   ::BREAK::

   -- Unicast forwarding.
   for i = 0, pft.ucast.length-1 do
      local pfe = pft.ucast.entries[i]
      local pl = pfe.plist
      transmit(ports[pl.ports[0]].l_out, pfe.p)
   end

   -- Multicast/Flooding forwarding.  The first packet is transmitted
   -- regularly.  All other packets need to be cloned from the first
   -- one.
   for i = 0, pft.flood.length-1 do
      local pfe = pft.flood.entries[i]
      local pl = pfe.plist
      transmit(ports[pl.ports[0]].l_out, pfe.p)
      for j = 1, pl.length-1 do
         transmit(ports[pl.ports[j]].l_out, clone(pfe.p))
      end
   end

   -- Discard packets that failed the split-horizon check.
   for i = 0, pft.discard.length-1 do
      local pfe = pft.discard.entries[i]
      packet.free(pfe.p)
   end
end
