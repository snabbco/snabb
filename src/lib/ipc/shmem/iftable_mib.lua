-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)
local lib = require("core.lib")
local mib = require("lib.ipc.shmem.mib")
local counter = require("core.counter")
local macaddress = require("lib.macaddress")
local logger = require("lib.logger")
local ffi = require("ffi")
local C = ffi.C

local iftypes = {
   [0x0000] =  1,  -- other
   [0x1000] =  6,  -- ethernetCsmacd
   [0x1001] = 53,  -- propVirtual
   [0x1002] = 135, -- l2vlan
   [0x1003] = 136, -- l3ipvlan
}

function init_snmp (objs, name, counters, directory, interval)
   -- Rudimentary population of a row in the ifTable MIB.  Allocation
   -- of the ifIndex is delegated to the SNMP agent via the name of
   -- the interface in ifDescr.
   local function get_counter (cname)
      if counters[cname] then
         return counter.read(counters[cname])
      else
         return nil
      end
   end
   local ifTable = mib:new({ directory = directory or nil,
                             filename = name })
   local logger = logger.new({ module = 'iftable_mib' })
   -- ifTable
   ifTable:register('ifDescr', 'OctetStr', objs.ifDescr)
   ifTable:register('ifType', 'Integer32')
   ifTable:set('ifType',
               iftypes[tonumber(get_counter('type') or 0)])
   ifTable:register('ifMtu', 'Integer32')
   ifTable:set('ifMtu', get_counter('mtu'))
   ifTable:register('ifSpeed', 'Gauge32')
   ifTable:register('ifHighSpeed', 'Gauge32')
   if counters.macaddr then
      ifTable:register('ifPhysAddress', { type = 'OctetStr', length = 6 })
      local mac = macaddress:new(get_counter('macaddr'))
      ifTable:set('ifPhysAddress', ffi.string(mac.bytes, 6))
   else
      ifTable:register('ifPhysAddress', { type = 'OctetStr', length = 0 })
   end
   ifTable:register('ifAdminStatus', 'Integer32', 1) -- up
   if counters.status then
      ifTable:register('ifOperStatus', 'Integer32', 2) -- down
   else
      logger:log("Operational status not available "
                 .."for interface "..objs.ifDescr)
      ifTable:register('ifOperStatus', 'Integer32', 1) -- up
   end
   ifTable:register('ifLastChange', 'TimeTicks', 0)
   ifTable:register('_X_ifLastChange_TicksBase', 'Counter64',
                    C.get_unix_time())
   ifTable:register('ifInOctets', 'Counter32', 0)
   ifTable:register('ifInUcastPkts', 'Counter32', 0)
   ifTable:register('ifInDiscards', 'Counter32', 0)
   ifTable:register('ifInErrors', 'Counter32', 0) -- TBD
   ifTable:register('ifInUnknownProtos', 'Counter32', 0) -- TBD
   ifTable:register('ifOutOctets', 'Counter32', 0)
   ifTable:register('ifOutUcastPkts', 'Counter32', 0)
   ifTable:register('ifOutDiscards', 'Counter32', 0)
   ifTable:register('ifOutErrors', 'Counter32', 0) -- TBD
   -- ifXTable
   ifTable:register('ifName', { type = 'OctetStr', length = 255 }, objs.ifName)
   ifTable:register('ifInMulticastPkts', 'Counter32', 0)
   ifTable:register('ifInBroadcastPkts', 'Counter32', 0)
   ifTable:register('ifOutMulticastPkts', 'Counter32', 0)
   ifTable:register('ifOutBroadcastPkts', 'Counter32', 0)
   ifTable:register('ifHCInOctets', 'Counter64', 0)
   ifTable:register('ifHCInUcastPkts', 'Counter64', 0)
   ifTable:register('ifHCInMulticastPkts', 'Counter64', 0)
   ifTable:register('ifHCInBroadcastPkts', 'Counter64', 0)
   ifTable:register('ifHCOutOctets', 'Counter64', 0)
   ifTable:register('ifHCOutUcastPkts', 'Counter64', 0)
   ifTable:register('ifHCOutMulticastPkts', 'Counter64', 0)
   ifTable:register('ifHCOutBroadcastPkts', 'Counter64', 0)
   ifTable:register('ifLinkUpDownTrapEnable', 'Integer32', 2) -- disabled
   ifTable:register('ifPromiscuousMode', 'Integer32', 2) -- false
   ifTable:register('ifConnectorPresent', 'Integer32', 1) -- true
   ifTable:register('ifAlias', { type = 'OctetStr', length = 64 },
                    objs.ifAlias) -- interface description
   ifTable:register('ifCounterDiscontinuityTime', 'TimeTicks', 0)
   ifTable:register('_X_ifCounterDiscontinuityTime', 'Counter64')
   ifTable:set('_X_ifCounterDiscontinuityTime', get_counter('dtime'))

   local status = { [1] = 'up', [2] = 'down' }
   local function t ()
      local old, new
      if counters.status then
         old = ifTable:get('ifOperStatus')
         new = tonumber(get_counter('status'))
         if old ~= new then
            logger:log("Interface "..objs.ifDescr..
                          " status change: "..status[old].." => "..status[new])
            ifTable:set('ifOperStatus', new)
            ifTable:set('ifLastChange', 0)
            ifTable:set('_X_ifLastChange_TicksBase', C.get_unix_time())
         end
      end

      local speed = get_counter('speed')
      if speed then
         if speed > 1000000000 then
            ifTable:set('ifSpeed', 4294967295) -- RFC3635 sec. 3.2.8
         else
            ifTable:set('ifSpeed', speed)
         end
         ifTable:set('ifHighSpeed', speed / 1000000)
      end
      ifTable:set('ifPromiscuousMode', get_counter('promisc'))
      ifTable:set('ifMtu', get_counter('mtu'))
      -- Update packet counters
      local rxpackets = get_counter('rxpackets')
      if rxpackets then
         local inUcast
         local rxbcast = get_counter('rxbcast')
         local rxmcast = get_counter('rxmcast')
         if rxmcast and rxbcast then
            local inMcast = rxmcast - rxbcast
            inUcast = rxpackets - rxmcast
            ifTable:set('ifHCInMulticastPkts', inMcast)
            ifTable:set('ifInMulticastPkts', inMcast)
            ifTable:set('ifHCInBroadcastPkts', rxbcast)
            ifTable:set('ifInBroadcastPkts', rxbcast)
         else
            inUcast = rxpackets
         end
         ifTable:set('ifHCInUcastPkts', inUcast)
         ifTable:set('ifInUcastPkts', inUcast)
      end
      local rxbytes = get_counter('rxbytes')
      if rxbytes then
         ifTable:set('ifHCInOctets', rxbytes)
         ifTable:set('ifInOctets', rxbytes)
      end
      ifTable:set('ifInDiscards', get_counter('rxdrop'))
      ifTable:set('ifInErrors', get_counter('rxerrors'))
      local txpackets = get_counter('txpackets')
      if txpackets then
         local outUcast
         local txbcast = get_counter('txbcast')
         local txmcast = get_counter('txmcast')
         if txmcast and txbcast then
            local outMcast = txmcast - txbcast
            outUcast = txpackets - txmcast
            ifTable:set('ifHCOutMulticastPkts', outMcast)
            ifTable:set('ifOutMulticastPkts', outMcast)
            ifTable:set('ifHCOutBroadcastPkts', txbcast)
            ifTable:set('ifOutBroadcastPkts', txbcast)
         else
            outUcast = txpackets
         end
         ifTable:set('ifHCOutUcastPkts', outUcast)
         ifTable:set('ifOutUcastPkts', outUcast)
      end
      local txbytes = get_counter('txbytes')
      if txbytes then
         ifTable:set('ifHCOutOctets', txbytes)
         ifTable:set('ifOutOctets', txbytes)
      end
      ifTable:set('ifOutDiscards', get_counter('txdrop'))
      ifTable:set('ifOutErrors', get_counter('txerrors'))
   end
   local t = timer.new("Interface "..name.." status checker",
                       t, 1e9 * (interval or 5), 'repeating')
   timer.activate(t)
   return t
end
