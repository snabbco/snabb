-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Base class for an Ethernet bridge with split-horizon semantics.
--
-- A bridge conists of any number of ports, each of which is a member
-- of at most one split-horizon group.  If it is not a member of a
-- split-horizon group, the port is also called a "free" port.
-- Packets arriving on a free port may be forwarded to all other
-- ports.  Packets arriving on a port that belongs to a split-horizon
-- group are never forwarded to any port belonging to the same
-- split-horizon group.
--
-- The configuration is passed as a table of the following form
--
-- config = { ports = { <free-port1>, <free-port2>, ... },
--            split_horizon_groups = {
--              <sh_group1> = { <shg1-port1>, <shg1-port2>, ...},
--              ...},
--            config = { <bridge-specific-config> } }
--
-- Port names have to be unique by themselves, irrespective of whether
-- they are free ports or belong to a split-horizon group.
--
-- The "config" table contains configuration options specific to a
-- derived class.  It is ignored by the base class.  A derived class
-- can access the configuration via self._conf.config.  If config is
-- not set, it is initialiezed to an empty table.
--
-- To make processing in the fast path easier, each port and group is
-- assigned a unique integer greater than zero to serve as a "handle".
-- The group handle 0 is assigned to all free ports.
--
-- The base constructor creates the following arrays as private
-- instance variables for efficient access in the push() method (which
-- must be provided by any derived class).
--
--  self._ports
--
--     Each port is assigned a table containing the following information
--
--         { name = <port-name>,
--           group = <group-handle>,
--           handle = <handle> }
--
--     The tables of all ports is stored in the self._ports table,
--     which can be indexed by both, the port name as well as the port
--     handle to access the information for a particular port.
--
--  self._dst_ports
--
--     This is an array which stores an array of egress port handles
--     for every ingress port handle.  According to the split-horizon
--     semantics, this includes all port handles except the ingress
--     handle and all handles that belong to the same group.
--
-- The push() method of a derived class should iterate over all source
-- ports and forward the incoming packets to the associated output
-- ports, replicating the packets as necessary.  In the simplest case,
-- the packets must be replicated to all destination ports (flooded)
-- to make sure they reach any potential recipient.  A more
-- sophisticated bridge can store the MAC source addresses on incoming
-- ports to limit the scope of flooding.

module(..., package.seeall)

bridge = subClass(nil)
bridge._name = "base bridge"
bridge.config = {
   ports = {required=true},
   split_horizon_groups = {},
   config = {default={}}
}

function bridge:new (conf)
   assert(self ~= bridge, "Can't instantiate abstract class "..self:name())
   local o = bridge:superClass().new(self)
   o._conf = conf

   -- Create a list of forwarding ports for all ports connected to the
   -- bridge, taking split horizon groups into account
   local ports, groups = {}, {}
   local function add_port(port, group)
      assert(not ports[port],
             self:name()..": duplicate definition of port "..port)
      local group_handle = 0
      if group then
         local desc = groups[group]
         if not desc then
            desc = { name = group, ports = {} }
            groups[group] = desc
            table.insert(groups, desc)
            desc.handle = #groups
         end
         group_handle = desc.handle
      end
      local desc = { name = port,
                     group = group_handle }
      ports[port] = desc
      table.insert(ports, desc)
      desc.handle = #ports
      if group_handle ~= 0 then
         table.insert(groups[group_handle].ports, desc.handle)
      end
   end

   -- Add free ports
   for _, port in ipairs(conf.ports) do
      add_port(port)
   end

   -- Add split horizon groups
   if conf.split_horizon_groups then
      for group, ports in pairs(conf.split_horizon_groups) do
         for _, port in ipairs(ports) do
            add_port(port, group)
         end
      end
   end

   -- Create list of egress ports for each ingress port, containing
   -- all free ports as well as all ports from different split-horizon
   -- groups
   local dst_ports = {}
   for sport, sdesc in ipairs(ports) do
      dst_ports[sport] = {}
      for dport, ddesc in ipairs(ports) do
         if not (sport == dport or (sdesc.group ~= 0 and
                                    sdesc.group == ddesc.group)) then
            table.insert(dst_ports[sport], dport)
         end
      end
   end
   o._groups = groups
   o._ports = ports
   o._dst_ports = dst_ports
   return o
end

-- API
--
-- Add the ingress and egress links to the port descriptor tables,
-- accessible via the keys l_in and l_out, respectively.  This helps
-- to speed up packet forwarding by eliminating a lookup in the input
-- and output tables.
function bridge:link ()
   assert(self.input and self.output)
   for _, port in ipairs(self._ports) do
      port.l_in = self.input[port.name]
      port.l_out = self.output[port.name]
   end
end

-- API
--
-- Print the port configuration and forwarding tables of the bridge.
-- This is primarily intended for debugging.
function bridge:info ()
   local ports, groups = self._ports, self._groups
   local function nh (n, h)
      return n.."("..h..")"
   end
   print("Free ports:")
   for p, desc in ipairs(ports) do
      if desc.group == 0 then
         print("\t"..nh(desc.name, p))
      end
   end
   print("Split-horizon groups:")
   for g, desc in ipairs(groups) do
      print("\t"..nh(desc.name, g)..", members:")
      for _, p in ipairs(desc.ports) do
         print("\t\t"..nh(ports[p].name, p))
      end
   end
   print("Forwarding tables:")
   for p, dst in ipairs(self._dst_ports) do
      print("\t"..nh(ports[p].name, p))
      for _, d in ipairs(dst) do
         print("\t\t"..nh(ports[d].name, d))
      end
   end
end
