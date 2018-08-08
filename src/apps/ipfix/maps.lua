module(..., package.seeall)

local ffi      = require("ffi")
local lib      = require("core.lib")
local ctable   = require("lib.ctable")
local ethernet = require("lib.protocol.ethernet")
local lpm      = require("lib.lpm.lpm4_248").LPM4_248
local logger   = require("lib.logger")

-- Map MAC addresses to peer AS number
--
-- Used to determine bgpPrevAdjacentAsNumber, bgpNextAdjacentAsNumber
-- from the packet's MAC addresses.  File format:
--   <AS>-<MAC>
local mac_to_as_key_t = ffi.typeof("uint8_t[6]")
local mac_to_as_value_t = ffi.typeof("uint32_t")

local function make_mac_to_as_map(name)
   local table = ctable.new({ key_type = mac_to_as_key_t,
                              value_type = mac_to_as_value_t,
                              initial_size = 15000 })
   local key = mac_to_as_key_t()
   local value = mac_to_as_value_t()
   for line in assert(io.lines(name)) do
      local as, mac = line:match("^%s*(%d*)-([0-9a-fA-F:]*)")
      assert(as and mac, "MAC-to-AS map: invalid line: "..line)
      local key, value = ethernet:pton(mac), tonumber(as)
      local result = table:lookup_ptr(key)
      if result then
         if result.value ~= value then
            print("MAC-to-AS map: amibguous mapping: "
                     ..ethernet:ntop(key)..": "..result.value..", "..value)
         end
      end
      table:add(key, value, true)
   end
   return table
end

-- Map VLAN tag to interface Index
--
-- Used to set ingressInterface, egressInterface based on the VLAN
-- tag.  This is useful if packets from multiple sources are
-- multiplexed on the input interface by a device between the metering
-- process and the port mirrors/optical taps of the monitored links.
-- The multiplexer adds a VLAN tag to uniquely identify the original
-- monitored link.  The tag is then translated into an interface
-- index.  Only one of the ingressInterface and egressInterface
-- elements is relevant, depending on the direction of the flow. File
-- format:
--   <TAG>-<ingress>-<egress>
local function make_vlan_to_ifindex_map(name)
   local table = {}
   for line in assert(io.lines(name)) do
      local vlan, ingress, egress = line:match("^(%d+)-(%d+)-(%d+)$")
      assert(vlan and ingress and egress,
             "VLAN-to-IFIndex map: invalid line: "..line)
      table[tonumber(vlan)] = {
         ingress = tonumber(ingress),
         egress = tonumber(egress)
      }
   end
   return table
end

-- Map IPv4 address to AS number
--
-- Used to set bgpSourceAsNumber, bgpDestinationAsNumber from the IPv4
-- source and destination address, respectively.  The file contains a
-- list of prefixes and their proper source AS number based on
-- authoritative data from the RIRs. This parser supports the format
-- used by the Geo2Lite database provided by MaxMind:
-- http://geolite.maxmind.com/download/geoip/database/GeoLite2-ASN-CSV.zip
local function make_pfx_to_as_map(name)
   local table = lpm:new({ keybits = 31 })
   -- Assign AS 0 to addresses not covered by the map
   table:add_string("0.0.0.0/0", 0)
   for line in assert(io.lines(name)) do
      if not line:match("^network") then
         local pfx, asn = line:match("([^,]*),(%d+),")
         assert(pfx and asn, "Prefix-to-AS map: invalid line: "..line)
         table:add_string(pfx, tonumber(asn))
      end
   end
   table:build()
   return table
end

local map_info = {
   mac_to_as = {
      create_fn = make_mac_to_as_map,
      logger_module = 'MAC to AS mapper'
   },
   vlan_to_ifindex = {
      create_fn = make_vlan_to_ifindex_map,
      logger_module = 'VLAN to ifIndex mapper'
   },
   pfx_to_as = {
      create_fn = make_pfx_to_as_map,
      logger_module = 'Prefix to AS mapper'
   }
}

local maps = {}

function mk_map(name, file, log_rate, log_fh)
   local info = assert(map_info[name])
   local map = maps[name]
   if not map then
      map = info.create_fn(file)
      maps[name] = map
   end
   local map = { map = map }
   if log_fh then
      map.logger = logger.new({ rate = log_rate or 0.05,
                                fh = log_fh,
                                module = info.logger_module })
   end
   return map
end
