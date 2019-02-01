module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local cc_proto = require("program.l2vpn.cc_proto")
local ipc_mib = require("lib.ipc.shmem.mib")
local datagram = require("lib.protocol.datagram")

-- Set SNMP OperStatus based on inbound/outbound status.  The
-- semantics are slightly different in the CISCO-IETF-PW-MIB and the
-- STD-PW-MIB.  For the former, the InboundOperStatus is simply set to
-- "up" whenever a heartbeat is received.  For the latter, more
-- detailed status information is advertised by the peer through the
-- signalling protocol, see the description of the pwRemoteStatus
-- object.  However, the control-channel does not currently implement
-- this and we treat the reception of a heartbeat like the reception
-- of a "no faults" status report.  In any case, cpwVcOperStatus and
-- pwOperStatus are always guaranteed to have the same value.
local oper_status = { [1] = 'up', [2] = 'down', [4] = 'unknown' }
local function set_OperStatus (self, mib)
   local old = mib:get('cpwVcOperStatus')
   if (mib:get('cpwVcInboundOperStatus') == 1 and
    mib:get('cpwVcOutboundOperStatus') == 1) then
      new = 1 -- up
   else
      new = 2 -- down
   end
   if new ~= old then
      mib:set('cpwVcOperStatus', new)
      mib:set('pwOperStatus', new)
      self._logger:log("Oper Status "..oper_status[old]..
                          " => "..oper_status[new])
      if new == 1 then
         local now = C.get_unix_time()
         mib:set('_X_cpwVcUpTime_TicksBase', now)
         mib:set('_X_pwUpTime_TicksBase', now)
         mib:set('_X_pwLastChange_TicksBase', now)
      else
         mib:set('_X_cpwVcUpTime_TicksBase', 0)
         mib:set('cpwVcUpTime', 0)
         mib:set('_X_pwUpTime_TicksBase', 0)
         mib:set('pwUpTime', 0)
         mib:set('_X_pwLastChange_TicksBase', C.get_unix_time())
      end
   end
end

local function set_InboundStatus_up (self, mib)
   mib:set('cpwVcInboundOperStatus', 1)
   mib:set('pwRemoteStatus', {}) -- no fault
   set_OperStatus(self, mib)
end

local function set_InboundStatus_down (self, mib)
   mib:set('cpwVcInboundOperStatus', 2)
   mib:set('pwRemoteStatus', { 0 }) -- pwNotForwarding
   set_OperStatus(self, mib)
end

local function increment_errors(self)
   self._mib:set('pwPerfTotalErrorPackets',
                 self._mib:get('pwPerfTotalErrorPackets') + 1)
   self._mib:set('cpwVcPerfTotalErrorPackets',
                 self._mib:get('cpwVcPerfTotalErrorPackets') + 1)
end

-- Process a control message
local cc_state = cc_proto.create_state()
local function process_cc (self, p)
   local mib = self._mib
   local status_ok = true
   local have_heartbeat_p = false
   local _cc = self._cc
   if not _cc then
      self._logger:log("Non-functional asymmetric control-channel "
                       .."remote enabled, local disabled)")
      set_InboundStatus_down(self, mib)
      return
   end

   cc_state.chunk[0], cc_state.len = p.data, p.length
   for tlv, errmsg in cc_proto.parse_next, cc_state do
      if errmsg then
         -- An error occured during parsing.  This renders the
         -- control-channel non-functional.
         self._logger:log("Invalid control-channel packet: "..errmsg)
         status_ok = false
         break
      end
      local type = cc_proto.types[tlv.h.type]
      if type.name == 'heartbeat' then
         have_heartbeat_p = true
         local hb = type.get(tlv)
         _cc.rcv_tstamp = math.floor(tonumber(C.get_time_ns())/1e9)
         if _cc.remote_hb == nil then
            self._logger:log("Starting remote heartbeat timer at "..hb
                                .." seconds")
            local t = _cc.timer_hb
            t.ticks = hb*1000
            t.repeating = true
            timer.activate(_cc.timer_hb)
            _cc.remote_hb = hb
         elseif _cc.remote_hb ~= hb then
            self._logger:log("Changing remote heartbeat "..
                                _cc.remote_hb.." => "..hb.." seconds")
            _cc.remote_hb = hb
            _cc.timer_hb.ticks = hb*1000
         end
      elseif type.name == 'mtu' then
         local mtu = type.get(tlv)
         local old_mtu = mib:get('cpwVcRemoteIfMtu')
         if mtu ~=  old_mtu then
            self._logger:log("Remote MTU change "..old_mtu.." => "..mtu)
         end
         mib:set('cpwVcRemoteIfMtu', type.get(tlv))
         mib:set('pwRemoteIfMtu', type.get(tlv))
         if mtu ~= self._mtu then
            self._logger:log("MTU mismatch, local "..self._mtu
                ..", remote "..mtu)
            status_ok = false
         end
      elseif type.name == 'if_description' then
         local old_ifs = mib:get('cpwVcRemoteIfString')
         local ifs = type.get(tlv)
         mib:set('cpwVcRemoteIfString', ifs)
         mib:set('pwRemoteIfString', ifs)
         if old_ifs ~= ifs then
            self._logger:log("Remote interface change '"
                                ..old_ifs.."' => '"..ifs.."'")
         end
      elseif type.name == 'vc_id' then
         if type.get(tlv) ~= self._vc_id then
            self._logger:log("VC ID mismatch, local "..self._vc_id
                ..", remote "..type.get(tlv))
            status_ok = false
         end
      end
   end

   if not have_heartbeat_p then
      self._logger:log("Heartbeat option missing in control message.")
      status_ok = false
   end
   if status_ok then
      set_InboundStatus_up(self, mib)
   else
      set_InboundStatus_down(self, mib)
   end
end

control_channel = {
   config = {
      enable = { default = false },
      heartbeat = { default = 10 },
      dead_factor = { default = 3 },
      send_repeat = { default = 3 },
      -- Name of the associated pseudowire. Used for
      --   pwName
      --   cpwVcName
      --   Logger module name
      --   shmem file
      name = { required = true },
      -- Description of the associated VPLS, same for
      -- all pseudowires
      description = { required = true },
      -- If the VPLS is point-to-point, local_if_name and
      -- local_if_alias contain the name and alias of the local AC.
      -- The name is used to derive the pwEnetPortIfIndex and
      -- cpwVcEnetPortIfIndex objects, the alias is transmitted to the
      -- peer via the CC.
      --
      -- If the VPLS is multi-point, both parameters must be
      -- nil. pwEnetPortIfIndex and cpwVcEnetPortIfIndex are set to
      -- zero and the name of the pseudowire is transmitted via the
      -- CC.
      local_if_name = { default = nil },
      local_if_alias = { default = nil },
      mtu = { required = true },
      vc_id = { required = true },
      afi = { required = true },
      peer_addr = { required = true },
      shmem_dir = { default = '/var/lib/snabb/shmem' },
   }
}

function control_channel:new (conf)
   local o = {
      _logger = lib.logger_new({
            module =
               ("Pseudowire %s: Peer: %s"):format(conf.name, conf.peer_addr)
      }),
      _mtu = conf.mtu,
      _vc_id = conf.vc_id
   }
   local peer_addr_bin =
      require("lib.protocol."..conf.afi):pton(conf.peer_addr)

   ---- Set up shared memory to interface with the SNMP sub-agent that
   ---- provides the MIBs related to the pseudowire.  The PWE3
   ---- architecture (Pseudo Wire Emulation Edge-to-Edge) described in
   ---- RFC3985 uses a layered system of MIBs to describe the service.
   -----
   ---- The top layer is called the "service layer" and describes the
   ---- emulated service (e.g. Ethernet).  The bottom layer is the
   ---- PSN-specific layer (Packet Switched Network) and describes how
   ---- the emulated service is transported across the underlying
   ---- network.  The middle layer provides the glue between these
   ---- layers and describes generic properties of the pseudowire
   ---- (i.e. properties that are independent of both, the emulated
   ---- service and the PSN). This layer is called the "generic PW
   ---- layer".
   ----
   ---- The standard MIB for the generic layer is called STD-PW-MIB,
   ---- defined in RFC5601.  Over 5 years old, Cisco still hasn't
   ---- managed to implement it on most of their devices at the time of
   ---- writing and uses a proprietary MIB based on a draft version
   ---- dating from 2004, available at
   ---- ftp://ftp.cisco.com/pub/mibs/v2/CISCO-IETF-PW-MIB.my
   ---- So, for the time being, we support both.  Sigh.
   ----
   ---- The MIB contains a table for every PW.  The objects pwType
   ---- (cpwVcType) and pwPsnType (cpwVcPsnType) indicate the types of
   ---- the service-specific and PSN-specific layers.  The tunnel
   ---- types supported by this implementation are not standardized.
   ---- This is expressed by the PsnType "other" and, as a
   ---- consequence, there is no MIB that describes the PSN-specific
   ---- layer.
   ----
   ---- The values 4 (tagged Ethernet) and 5 (Ethernet)
   ---- pwType (cpwVcType) identify the service-specific MIB to be
   ---- PW-ENET-STD-MIB defined by RFC5603.  Again, Cisco didn't
   ---- bother to implement the standard and keeps using a proprietary
   ---- version based on a draft of RFC5603 called
   ---- CISCO-IETF-PW-ENET-MIB, available from
   ---- ftp://ftp.cisco.com/pub/mibs/v2/CISCO-IETF-PW-ENET-MIB.my.
   ----
   ---- The rows of the ENET MIB are indexed by the same value as
   ---- those of the STD-PW-MIB (pwIndex/cpwVcIndex, managed by the
   ---- SNMP agent).  They have a second index that makes rows unique
   ---- which are associated with the same PW in the case of tagged
   ---- ACs.

   local mib = ipc_mib:new({ directory = conf.shmem_dir,
                             filename = conf.name })

   --
   -- STD-PW-MIB
   --
   mib:register('pwType', 'Integer32', 5) -- Ethernet
   mib:register('pwOwner', 'Integer32', 1) -- manual
   -- The PSN Type indicates how the PW is transported over the
   -- underlying packet switched network.  It's purpose is to identify
   -- which MIB is used at the "PSN VC Layer according to the
   -- definition in RFC 3985, Section 8. The encapsulations
   -- implemented in the current version are not covered by the
   -- PsnType, hence the choice of "other".
   mib:register('pwPsnType', 'Integer32', 6) -- other
   mib:register('pwSetUpPriority', 'Integer32', 0) -- unused
   mib:register('pwHoldingPriority', 'Integer32', 0) -- unused
   if conf.afi == 'ipv6' then
      mib:register('pwPeerAddrType', 'Integer32', 2) -- IPv6
      mib:register('pwPeerAddr', { type = 'OctetStr', length = 16 },
                   ffi.string(peer_addr_bin, 16))
   elseif conf.afi == 'ipv4' then
      mib:register('pwPeerAddrType', 'Integer32', 1) -- IPv4
      mib:register('pwPeerAddr', { type = 'OctetStr', length = 4 },
                   ffi.string(peer_addr_bin, 4))
   else
      error("Invalid address family : "..conf.afi)
   end
   mib:register('pwAttachedPwIndex', 'Unsigned32', 0)
   mib:register('pwIfIndex', 'Integer32', 0)
   assert(conf.vc_id, "missing VC ID")
   mib:register('pwID', 'Unsigned32', conf.vc_id)
   mib:register('pwLocalGroupID', 'Unsigned32', 0) -- unused
   mib:register('pwGroupAttachmentID', { type = 'OctetStr', length = 0}) -- unused
   mib:register('pwLocalAttachmentID', { type = 'OctetStr', length = 0}) -- unused
   mib:register('pwRemoteAttachmentID', { type = 'OctetStr', length = 0}) -- unused
   mib:register('pwCwPreference', 'Integer32', 2) -- false
   mib:register('pwLocalIfMtu', 'Unsigned32', conf.mtu)
   mib:register('pwLocalIfString', 'Integer32', 1) -- true
   -- We advertise the pwVCCV capability, even though our "control
   -- channel" protocol is proprietary.
   mib:register('pwLocalCapabAdvert', 'Bits', { 1 }) -- pwVCCV
   mib:register('pwRemoteGroupID', 'Unsigned32', 0) -- unused
   mib:register('pwCwStatus', 'Integer32', 6) -- cwNotPresent
   mib:register('pwRemoteIfMtu', 'Unsigned32', 0) -- not yet known
   mib:register('pwRemoteIfString', { type = 'OctetStr',
                                         length = 80 }, '') -- not yet known
   mib:register('pwRemoteCapabilities', 'Bits', { 1 }) -- pwVCCV, see pwLocalCapabAdvert
   mib:register('pwFragmentCfgSize', 'Unsigned32', 0) -- fragmentation not desired
   -- Should be advertised on the CC
   mib:register('pwRmtFragCapability', 'Bits', { 0 }) -- NoFrag
   mib:register('pwFcsRetentionCfg', 'Integer32', 1) -- fcsRetentionDisable
   mib:register('pwFcsRetentionStatus', 'Bits', { 3 }) -- fcsRetentionDisabled

   -- TODO
   -- mib:register('pwOutboundLabel', 'Unsigned32', 0)
   -- mib:register('pwInboundLabel', 'Unsigned32', 0)

   mib:register('pwName', 'OctetStr', conf.name)
   mib:register('pwDescr', 'OctetStr', conf.description)
   -- We record the PW creation time as a regular timestamp in a
   -- auxiliary 64-bit variable with the suffix "_TimeAbs".  The SNMP
   -- agent recognises this convention and calculates the actual
   -- TimeStamp object from it (defined as the difference between two epochs
   -- of the sysUpTime object).
   mib:register('pwCreateTime', 'TimeTicks')
   mib:register('_X_pwCreateTime_TimeAbs', 'Counter64',
                C.get_unix_time())
   -- The absolute time stamp when the VC transitions to the "up"
   -- state is recorded in the auxiliary variable with the suffix
   -- "_TicksBase".  The SNMP agent recognises this convention and
   -- calculates the actual TimeTicks object as the difference between
   -- the current time and this timestamp, unless the time stamp has
   -- the value 0, in which case the actual object will be used.
   mib:register('pwUpTime', 'TimeTicks', 0)
   mib:register('_X_pwUpTime_TicksBase', 'Counter64', 0)
   mib:register('pwLastChange', 'TimeTicks', 0)
   mib:register('_X_pwLastChange_TicksBase', 'Counter64', 0)
   mib:register('pwAdminStatus', 'Integer32', 1) -- up
   mib:register('pwOperStatus', 'Integer32', 2) -- down
   mib:register('pwLocalStatus', 'Bits', {}) -- no faults
   -- The remote status capability is statically set to
   -- "remoteCapable" due to the presence of the control channel. The
   -- remote status is inferred from the reception of heartbeats.
   -- When heartbeats are received, the remote status is set to no
   -- faults (no bits set).  If the peer is declared dead, the status
   -- is set to pwNotForwarding.  Complete fault signalling may be
   -- implemented in the future.
   --
   -- XXX if the control-channel is disabled, we should mark remote as
   -- not status capable, since we are not able to determine the status.
   mib:register('pwRemoteStatusCapable', 'Integer32', 3) -- remoteCapable
   mib:register('pwRemoteStatus', 'Bits', { 0 }) -- pwNotForwarding
   -- pwTimeElapsed, pwValidIntervals not implemented
   mib:register('pwRowStatus', 'Integer32', 1) -- active
   mib:register('pwStorageType', 'Integer32', 2) -- volatile
   mib:register('pwOamEnable', 'Integer32', 2) -- false
   -- AII/AGI not applicable
   mib:register('pwGenAGIType', 'Unsigned32', 0)
   mib:register('pwGenLocalAIIType', 'Unsigned32', 0)
   mib:register('pwGenRemoteAIIType', 'Unsigned32', 0)
   -- The MIB contains a scalar object as a global (PW-independent)
   -- error counter.  Due to the design of the pseudowire app, each
   -- instance counts its errors independently.  The scalar variable
   -- is thus part of the mib table of each PW.  The SNMP agent is
   -- configured to accumulate the counters for each PW and serve this
   -- sum to SNMP clients for a request of this scalar object.
   mib:register('pwPerfTotalErrorPackets', 'Counter32', 10)

   --
   -- CISCO-IETF-PW-MIB
   --
   mib:register('cpwVcType', 'Integer32', 5) -- Ethernet
   mib:register('cpwVcOwner', 'Integer32', 1) -- manual
   mib:register('cpwVcPsnType', 'Integer32', 6) -- other
   mib:register('cpwVcSetUpPriority', 'Integer32', 0) -- unused
   mib:register('cpwVcHoldingPriority', 'Integer32', 0) -- unused
   mib:register('cpwVcInboundMode', 'Integer32', 2) -- strict
   if conf.afi == 'ipv6' then
      mib:register('cpwVcPeerAddrType', 'Integer32', 2) -- IPv6
      mib:register('cpwVcPeerAddr', { type = 'OctetStr', length = 16 },
                   ffi.string(peer_addr_bin, 16))
   elseif conf.afi == "ipv4" then
      mib:register('cpwVcPeerAddrType', 'Integer32', 1) -- IPv4
      mib:register('cpwVcPeerAddr', { type = 'OctetStr', length = 4 },
                   ffi.string(peer_addr_bin, 4))
   end
   mib:register('cpwVcID', 'Unsigned32', conf.vc_id)
   mib:register('cpwVcLocalGroupID', 'Unsigned32', 0) -- unused
   mib:register('cpwVcControlWord', 'Integer32', 2) -- false
   mib:register('cpwVcLocalIfMtu', 'Unsigned32', conf.mtu)
   mib:register('cpwVcLocalIfString', 'Integer32', 1) -- true
   mib:register('cpwVcRemoteGroupID', 'Unsigned32', 0) -- unused
   mib:register('cpwVcRemoteControlWord', 'Integer32', 1) -- noControlWord
   mib:register('cpwVcRemoteIfMtu', 'Unsigned32', 0) -- not yet known
   mib:register('cpwVcRemoteIfString', { type = 'OctetStr',
                                         length = 80 }, '') -- not yet known

   -- TODO
   -- mib:register('cpwVcOutboundVcLabel', 'Unsigned32', 0)
   -- mib:register('cpwVcInboundVcLabel', 'Unsigned32', 0)

   mib:register('cpwVcName', 'OctetStr', conf.name)
   mib:register('cpwVcDescr', 'OctetStr', conf.description)
   mib:register('cpwVcCreateTime', 'TimeTicks')
   mib:register('_X_cpwVcCreateTime_TimeAbs', 'Counter64',
                C.get_unix_time())
   mib:register('cpwVcUpTime', 'TimeTicks', 0)
   mib:register('_X_cpwVcUpTime_TicksBase', 'Counter64', 0)
   mib:register('cpwVcAdminStatus', 'Integer32', 1) -- up
   mib:register('cpwVcOperStatus', 'Integer32', 2) -- down
   mib:register('cpwVcInboundOperStatus', 'Integer32', 2) -- down
   mib:register('cpwVcOutboundOperStatus', 'Integer32', 1) -- up
   -- cpwVcTimeElapsed, cpwVcValidIntervals not implemented
   mib:register('cpwVcRowStatus', 'Integer32', 1) -- active
   mib:register('cpwVcStorageType', 'Integer32', 2) -- volatile
   -- See comment for pwPerfTotalErrorPackets
   mib:register('cpwVcPerfTotalErrorPackets', 'Counter64', 0)

   --
   -- PW-ENET-STD-MIB
   --
   mib:register('pwEnetPwInstance', 'Unsigned32', 1)
   mib:register('pwEnetPwVlan', 'Integer32', 4095) -- raw mode, map all frames to the PW
   mib:register('pwEnetVlanMode', 'Integer32', 1) -- portBased
   mib:register('pwEnetPortVlan', 'Integer32', 4095)
   mib:register('pwEnetPortIfIndex', 'Integer32', 0)
   mib:register('_X_pwEnetPortIfIndex', 'OctetStr', conf.local_if_name or '')
   mib:register('pwEnetPwIfIndex', 'Integer32', 0) -- PW not modelled as ifIndex
   mib:register('pwEnetRowStatus', 'Integer32', 1) -- active
   mib:register('pwEnetStorageType', 'Integer32', 2) -- volatile

   --
   -- CISCO-IETF-PW-ENET-MIB
   --
   mib:register('cpwVcEnetPwVlan', 'Integer32', 4097) -- raw mode, map all frames to the PW
   mib:register('cpwVcEnetVlanMode', 'Integer32', 1) -- portBased
   mib:register('cpwVcEnetPortVlan', 'Integer32', 4097)
   mib:register('cpwVcEnetPortIfIndex', 'Integer32', 0)
   mib:register('_X_cpwVcEnetPortIfIndex', 'OctetStr', conf.local_if_name or '')
   mib:register('cpwVcEnetVcIfIndex', 'Integer32', 0) -- PW not modelled as ifIndex
   mib:register('cpwVcEnetRowStatus', 'Integer32', 1) -- active
   mib:register('cpwVcEnetStorageType', 'Integer32', 2) -- volatile

   o._mib = mib

   if conf.enable then
      -- Create a static packet to transmit on the control channel
      local dgram = datagram:new(packet.allocate())
      cc_proto.add_tlv(dgram, 'heartbeat', conf.heartbeat)
      cc_proto.add_tlv(dgram, 'mtu', conf.mtu)
      -- The if_description ends up in the
      -- pwRemoteIfString/cpwVCRemoteIfString MIB objects.  The
      -- CISCO-IETF-PW-MIB refers to this value as the "interface's
      -- name as appears on the ifTable".  The STD-PW-MIB is more
      -- specific and defines the value to be sent to be the ifAlias
      -- of the local interface.  If the VPLS is multi-point, use
      -- the name of the pseudowire instead.
      cc_proto.add_tlv(dgram, 'if_description',
                 conf.local_if_alias or conf.name)
      cc_proto.add_tlv(dgram, 'vc_id', conf.vc_id)

      o._cc = {}

      -- Set up control-channel processing
      o._cc.timer_xmit = timer.new(conf.vc_id.." control-channel xmit",
                                   function (t)
                                      for _ = 1, conf.send_repeat do
                                         link.transmit(o.output.south,
                                                       packet.clone(dgram:packet()))
                                      end
                                   end,
                                   1e9 * conf.heartbeat, 'repeating')
      o._cc.timer_hb = timer.new(conf.vc_id.." control-channel heartbeat",
                                 function(t)
                                    if mib:get('cpwVcInboundOperStatus') == 1 then
                                       local now = math.floor(tonumber(C.get_time_ns())/1e9)
                                       local diff = now - o._cc.rcv_tstamp
                                       local hb = o._cc.remote_hb
                                       if diff > hb then
                                          o._logger:log("Missed remote heartbeat, dead in "
                                                           ..(hb*(conf.dead_factor+1)-diff).." seconds")
                                       end
                                       if diff > hb * conf.dead_factor then
                                          o._logger:log("Peer declared dead")
                                          set_InboundStatus_down(o, mib)
                                          -- Disable timer. It will be
                                          -- restarted when heartbeats
                                          -- start coming in again
                                          o._cc.remote_hb = nil
                                          o._cc.timer_hb.repeating = false
                                       end
                                    end
                                 end,
                                 0)
      timer.activate(o._cc.timer_xmit)
   end

   return setmetatable(o, { __index = control_channel })
end

function control_channel:push ()
   for _ = 1, link.nreadable(self.input.south) do
      local p = link.receive(self.input.south)
      process_cc(self, p)
      packet.free(p)
   end
end
