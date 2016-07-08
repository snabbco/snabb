-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)
local mib = require("lib.ipc.shmem.mib")
local counter = require("core.counter")
local macaddress = require("lib.macaddress")
local ffi = require("ffi")

local iftypes = {
   [0x1000] =  6, -- ethernetCsmacd
   [0x1001] = 53, -- propVirtual
}

function init_snmp (name, counters, directory, interval)
   -- Rudimentary population of a row in the ifTable MIB.  Allocation
   -- of the ifIndex is delegated to the SNMP agent via the name of
   -- the interface in ifDescr.
   local ifTable = mib:new({ directory = directory or nil,
                             filename = name })
   -- ifTable
   ifTable:register('ifDescr', 'OctetStr', name)
   ifTable:register('ifType', 'Integer32')
   if counters.type then
      ifTable:set('ifType', iftypes[counter.read(counters.type)] or 1) -- other
   end
   ifTable:register('ifMtu', 'Integer32')
   if counters.mtu then
      ifTable:set('ifMtu', counter.read(counters.mtu))
   end
   ifTable:register('ifSpeed', 'Gauge32')
   ifTable:register('ifHighSpeed', 'Gauge32')
   if counters.speed then
      speed = counters.read(counters.speed)
      if speed > 1000000000 then
         ifTable:set('ifSpeed', 4294967295) -- RFC3635 sec. 3.2.8
      else
         ifTable:set('ifSpeed', speed)
      end
      ifTable:set('ifHighSpeed', speed / 1000000)
   end
   ifTable:register('ifPhysAddress', { type = 'OctetStr', length = 6 })
   if counters.macaddr then
      local mac = macaddress:new(counter.read(counters.macaddr))
      ifTable:set('ifPhysAddress', ffi.string(mac.bytes, 6))
   end
   ifTable:register('ifAdminStatus', 'Integer32', 1) -- up
   ifTable:register('ifOperStatus', 'Integer32', 2) -- down
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
   ifTable:register('ifName', { type = 'OctetStr', length = 255 }, name)
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
                    name) -- TBD add description
   ifTable:register('ifCounterDiscontinuityTime', 'TimeTicks', 0)
   ifTable:register('_X_ifCounterDiscontinuityTime', 'Counter64')
   if counters.dtime then
      ifTable:set('_X_ifCounterDiscontinuityTime', counter.read(counters.dtime))
   end

   local logger = lib.logger_new({ module = 'iftable_mib' })
   local function t ()
      local old, new
      if counters.status then
         old = ifTable:get('ifOperStatus')
         new = counter.read(counters.status)
      else
         new = 1
      end
      if old ~= new then
         logger:log("Interface "..name..
                    " status change: "..status[old].." => "..status[new])
         ifTable:set('ifOperStatus', new)
         ifTable:set('ifLastChange', 0)
         ifTable:set('_X_ifLastChange_TicksBase', C.get_unix_time())
      end

      if counters.promisc then
         ifTable:set('ifPromiscuousMode', counter.read(counters.promisc))
      end
      -- Update counters
      if counters.rxpackets and counters.rxmcast and counters.rxbcast then
         local rxbcast = counter.read(counters.rxbcast)
         local rxmcast = counter.read(counters.rxmcast)
         local rxpackets = counter.read(counters.rxpackets)
         local inMcast = rxmcast - rxbcast
         local inUcast = rxpackets - rxmcast
         ifTable:set('ifHCInMulticastPkts', inMcast)
         ifTable:set('ifInMulticastPkts', inMcast)
         ifTable:set('ifHCInBroadcastPkts', rxbcast)
         ifTable:set('ifInBroadcastPkts', rxbcast)
         ifTable:set('ifHCInUcastPkts', inUcast)
         ifTable:set('ifInUcastPkts', inUcast)
      end
      if counters.rxbytes then
         local rxbytes = counter.read(counters.rxbytes)
         ifTable:set('ifHCInOctets', rxbytes)
         ifTable:set('ifInOctets', rxbytes)
      end
      if counters.rxdrop then
         ifTable:set('ifInDiscards', counter.read(counters.rxdrop))
      end
      if counters.rxerrors then
         ifTable:set('ifInErrors', counter.read(counters.rxerrors))
      end
      if counters.txpackets and counters.txmcast and counters.txbcast then
         local txbcast = counter.read(counters.txbcast)
         local txmcast = counter.read(counters.txmcast)
         local txpackets = counter.read(counters.txpackets)
         local outMcast = txmcast - txbcast
         local outUcast = txpackets - txmcast
         ifTable:set('ifHCOutMulticastPkts', outMcast)
         ifTable:set('ifOutMulticastPkts', outMcast)
         ifTable:set('ifHCOutBroadcastPkts', txbcast)
         ifTable:set('ifOutBroadcastPkts', txbcast)
         ifTable:set('ifHCOutUcastPkts', outUcast)
         ifTable:set('ifOutUcastPkts', outUcast)
      end
      if counters.txbytes then
         local txbytes = counter.read(counters.txbytes)
         ifTable:set('ifHCOutOctets', txbytes)
         ifTable:set('ifOutOctets', txbytes)
      end
      if counters.txdrop then
         ifTable:set('ifOutDiscards', counter.read(counters.txdrop))
      end
      if counters.txerrors then
         ifTable:set('ifOutErrors', counter.read(counters.txerrors))
      end
   end
   local t = timer.new("Interface "..name.." status checker",
                       t, 1e9 * (interval or 5), 'repeating')
   timer.activate(t)
   return t
end
