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
-- The "config" table contains configuration options specific to a
-- derived class.  It is ignored by the base class.
--
-- The base constructor checks the configuration and creates the
-- following arrays as private instance variables for efficient access
-- in the push() method (which must be provided by any derived class).
--
--  self._src_ports
--
--     This array contains the names of all ports connected to the
--     bridge.
--
--  self._dst_ports
--
--     This table is keyed by the name of an input port and associates
--     it with an array of output ports according to the split-horizon
--     topology.
--
-- The push() method of a derived class should iterate over all source
-- ports and forward the incoming packets to the associated output
-- ports, replicating the packets as necessary.  In the simplest case,
-- the packets must be replicated to all destination ports (flooded)
-- to make sure they reach any potential recipient.  A more
-- sophisticated bridge can store the MAC source addresses on incoming
-- ports to limit the scope of flooding.

module(..., package.seeall)
local config = require("core.config")

bridge = subClass(nil)
bridge._name = "base bridge"

function bridge:new (arg)
   assert(self ~= bridge, "Can't instantiate abstract class "..self:name())
   local o = bridge:superClass().new(self)
   local conf = arg and config.parse_app_arg(arg) or {}
   assert(conf.ports, self._name..": invalid configuration")
   o._conf = conf

   -- Create a list of forwarding ports for all ports connected to the
   -- bridge, taking split horizon groups into account
   local ports = {}
   local function add_port(port, group)
      assert(not ports[port],
	     self:name()..": duplicate definition of port "..port)
      ports[port] = group
   end
   for _, port in ipairs(conf.ports) do
      add_port(port, '')
   end
   if conf.split_horizon_groups then
      for group, ports in pairs(conf.split_horizon_groups) do
	 for _, port in ipairs(ports) do
	    add_port(port, group)
	 end
      end
   end
   local src_ports, dst_ports = {}, {}
   for sport, sgroup in pairs(ports) do
      table.insert(src_ports, sport)
      dst_ports[sport] = {}
      for dport, dgroup in pairs(ports) do
	 if not (sport == dport or (sgroup ~= '' and sgroup == dgroup)) then
	    table.insert(dst_ports[sport], dport)
	 end
      end
   end
   o._src_ports = src_ports
   o._dst_ports = dst_ports
   return o
end
