-- Simplified implementation of a pseudowire based on RFC 4664,
-- providing a L2 point-to-point VPN on top of IPv6.
--
-- This app has two connections, ac (Attachment Circuit) and uplink.
-- The former transports Ethernet frames while the latter transports
-- Ethernet frames encapsulated in IPv6 and a suitable tunneling
-- protocol.  The push() method performs encapsulation between the ac
-- and uplink port and decapsulation between the uplink and ac ports,
-- respectively
--
-- The ac port can either attach directly to a physical device or a
-- "forwarder" in RFC 4664 terminology that handles
-- multiplexing/de-multiplexing of traffic between the actual AC and a
-- set of pseudowires to implement a multi-point L2 VPN.  An instance
-- of such a forwarder is provided by the apps/bridge module.
--
-- The app currently supports IPv6 as transport protocol and GRE or a
-- variant of L2TPv3 known as "keyed IPv6 tunnel" as tunnel protocol.
--
-- The encapsulation includes a full Ethernet header with dummy values
-- for the src/dst MAC addresses. On its "uplink" link, the app
-- connects to a L3 interface, represented by a neiaghbor-discovery app
-- which fills in the actual src/dst MAC addresses.

module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local app = require("core.app")
local link = require("core.link")
local config = require("core.config")
local timer = require("core.timer")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local packet = require("core.packet")
local filter = require("lib.pcap.filter")
local pcap = require("apps.pcap.pcap")
local cc = require("program.l2vpn.control_channel")
local ipc_mib = require("lib.ipc.shmem.mib")
local logger = require("lib.logger")

pseudowire = subClass(nil)
pseudowire._name = "Pseudowire"

local dgram_options = { delayed_commit = true }

local function log(self, msg, print_peer)
   if print_peer then
      msg = "Peer "..self._transport.peer..": "..msg
   end
   self._logger:log(msg)
end

-- Defaults for the control channel
local cc_defaults = { heartbeat = 10, dead_factor = 3 }

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
      log(self, "Oper Status "..oper_status[old]..
          " => "..oper_status[new], true)
      if new == 1 then
         local now = C.get_unix_time()
         mib:set('_X_cpwVcUpTime_TicksBase', now)
         mib:set('_X_pwUpTime_TicksBase', now)
         mib:set('_X_pwLastChange_TicksBase', now)
         -- Allow forwarding in push()
         self._forward = true
      else
         mib:set('_X_cpwVcUpTime_TicksBase', 0)
         mib:set('cpwVcUpTime', 0)
         mib:set('_X_pwUpTime_TicksBase', 0)
         mib:set('pwUpTime', 0)
         mib:set('_X_pwLastChange_TicksBase', C.get_unix_time())
         -- Stop forwarding in push()
         self._forward = false
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
local cc_state = cc.create_state()
local function process_cc (self, datagram)
   local mib = self._mib
   local status_ok = true
   local have_heartbeat_p = false
   local _cc = self._cc
   if not _cc then
      log(self, "Non-functional asymmetric control-channel "
          .."remote enabled, local disabled)", true)
      set_InboundStatus_down(self, mib)
      return
   end

   cc_state.chunk[0], cc_state.len = datagram:payload()
   for tlv, errmsg in cc.parse_next, cc_state do
      if errmsg then
         -- An error occured during parsing.  This renders the
         -- control-channel non-functional.
         log(self, "Invalid control-channel packet: "..errmsg, true)
         status_ok = false
         break
      end
      local type = cc.types[tlv.h.type]
      if type.name == 'heartbeat' then
         have_heartbeat_p = true
         local hb = type.get(tlv)
         _cc.rcv_tstamp = math.floor(tonumber(C.get_time_ns())/1e9)
         if _cc.remote_hb == nil then
            log(self, "Starting remote heartbeat timer at "..hb
                .." seconds", true)
            local t = _cc.timer_hb
            t.ticks = hb*1000
            t.repeating = true
            timer.activate(_cc.timer_hb)
            _cc.remote_hb = hb
         elseif _cc.remote_hb ~= hb then
            log(self, "Changing remote heartbeat "..
                _cc.remote_hb.." => "..hb.." seconds", true)
            _cc.remote_hb = hb
            _cc.timer_hb.ticks = hb*1000
         end
      elseif type.name == 'mtu' then
         local mtu = type.get(tlv)
         local old_mtu = mib:get('cpwVcRemoteIfMtu')
         if mtu ~=  old_mtu then
            log(self, "Remote MTU change "..old_mtu.." => "..mtu, true)
         end
         mib:set('cpwVcRemoteIfMtu', type.get(tlv))
         mib:set('pwRemoteIfMtu', type.get(tlv))
         if mtu ~= self._conf.mtu then
            log(self, "MTU mismatch, local "..self._conf.mtu
                ..", remote "..mtu, true)
            status_ok = false
         end
      elseif type.name == 'if_description' then
         local old_ifs = mib:get('cpwVcRemoteIfString')
         local ifs = type.get(tlv)
         mib:set('cpwVcRemoteIfString', ifs)
         mib:set('pwRemoteIfString', ifs)
         if old_ifs ~= ifs then
            log(self, "Remote interface change '"
                ..old_ifs.."' => '"..ifs.."'", true)
         end
      elseif type.name == 'vc_id' then
         if type.get(tlv) ~= self._conf.vc_id then
            log(self, "VC ID mismatch, local "..self._conf.vc_id
                ..", remote "..type.get(tlv), true)
            status_ok = false
         end
      end
   end

   if not have_heartbeat_p then
      log(self, "Heartbeat option missing in control message.", true)
      status_ok = false
   end
   if status_ok then
      set_InboundStatus_up(self, mib)
   else
      set_InboundStatus_down(self, mib)
   end
end

-- Configuration options
--  {
--    name = <name>,
--    mtu = <mtu>,
--    vc_id   = <vc_id>,
--    ac = <interface>,
--    [ shmem_dir = <shmem-dir>, ]
--    transport = { type = 'ipv6',
--                  [hop_limit = <hop_limit>],
--                  src  = <vpn_source>,
--                  dst  = <vpn_destination> }
--    tunnel = { type = 'gre' | 'l2tpv3',
--               -- type gre
--               [checksum = true | false],
--               [key = <key> | nil]
--               -- type l2tpv3
--               [local_session = <local_session> | nil,]
--               [remote_session = <remote_session> | nil,]
--               [local_cookie = <cookie> | nil],
--               [remote_cookie = <cookie> | nil] } }
--    [ cc = { [ heartbeat = <heartbeat>, ]
--             [ dead_factor = <dead_factor>, ]
--           } ]
--  }
function pseudowire:new (conf_in)
   local conf = conf_in or {}
   local o = pseudowire:superClass().new(self)
   o._conf = conf
   local bpf_program

   o._logger = logger.new({ module = o._name.." ("..o._conf.name..")" })
   -- Construct templates for the entire encapsulation chain

   -- Ethernet header
   --
   -- Use dummy values for the MAC addresses.  The actual addresses
   -- will be filled in by the ND-app to which the PW's uplink
   -- connects.
   o._ether = ethernet:new({ src = ethernet:pton('00:00:00:00:00:00'),
                             dst = ethernet:pton('00:00:00:00:00:00'),
                             type = 0x86dd })

   -- Tunnel header
   assert(conf.tunnel, "missing tunnel configuration")
   -- The control-channel is de-activated if either no
   -- configuration is present or if the heartbeat interval
   -- is set to 0.
   local have_cc = (conf.cc and not (conf.cc.heartbeat and
                                        conf.cc.heartbeat == 0))
   o._tunnel = require("program.l2vpn.tunnels."..
                       conf.tunnel.type):new(conf.tunnel, have_cc, o._logger)

   -- Transport header
   assert(conf.transport, "missing transport configuration")
   o._transport = require("program.l2vpn.transports."..
                          conf.transport.type):new(conf.transport, o._tunnel.proto,
                                                o._logger)
   o._decap_header_size = ethernet:sizeof() + o._transport.header:sizeof()

   -- We want to avoid copying the encapsulation headers one by one in
   -- the push() loop.  For this purpose, we create a template
   -- datagram that contains only the headers, which can be prepended
   -- to the data packets with a single call to push_raw().  In order
   -- to be able to update the headers before copying, we re-locate
   -- the headers to the payload of the template packet.
   local template = datagram:new(packet.allocate())
   template:push(o._tunnel.header)
   template:push(o._transport.header)
   template:push(o._ether)
   template:new(template:packet(), ethernet) -- Reset the parse stack
   o._tunnel.header:free()
   o._transport.header:free()
   o._ether:free()
   template:parse_n(3)
   o._ether, o._tunnel.transport, o._tunnel.header = unpack(template:stack())
   o._template = template

   -- Create a packet filter for the tunnel protocol
   bpf_program = " ip6 proto "..o._tunnel.proto
   local filter, errmsg = filter:new(bpf_program)
   assert(filter, errmsg and ffi.string(errmsg))
   o._filter = filter

   -- Create a datagram for re-use in the push() loop
   o._dgram = datagram:new(nil, nil, dgram_options)
   packet.free(o._dgram:packet())

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

   local mib = ipc_mib:new({ directory = conf.shmem_dir or '/tmp/snabb-shmem',
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
   mib:register('pwPeerAddrType', 'Integer32', 2) -- IPv6
   mib:register('pwPeerAddr', { type = 'OctetStr', length = 16},
                   ffi.string(conf.transport.dst, 16))
   mib:register('pwAttachedPwIndex', 'Unsigned32', 0)
   mib:register('pwIfIndex', 'Integer32', 0)
   assert(conf.vc_id, "missing VC ID")
   mib:register('pwID', 'Unsigned32', conf.vc_id)
   mib:register('pwLocalGroupID', 'Unsigned32', 0) -- unused
   mib:register('pwGroupAttachmentID', { type = 'OctetStr', length = 0}) -- unused
   mib:register('pwLocalAttachmentID', { type = 'OctetStr', length = 0}) -- unused
   mib:register('pwRemoteAttachmentID', { type = 'OctetStr', length = 0}) -- unused
   mib:register('pwCwPreference', 'Integer32', 2) -- false
   assert(conf.mtu, "missing MTU")
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
   if o._tunnel.OutboundVcLabel ~= nil then
      mib:register('pwOutboundLabel', 'Unsigned32', o._tunnel.OutboundVcLabel)
   end
   if o._tunnel.InboundVcLabel ~= nil then
      mib:register('pwInboundLabel', 'Unsigned32', o._tunnel.InboundVcLabel)
   end
   mib:register('pwName', 'OctetStr', conf.interface)
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
   mib:register('cpwVcPeerAddrType', 'Integer32', 2) -- IPv6
   mib:register('cpwVcPeerAddr', { type = 'OctetStr', length = 16},
                   ffi.string(conf.transport.dst, 16))
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
   if o._tunnel.OutboundVcLabel ~= nil then
      mib:register('cpwVcOutboundVcLabel', 'Unsigned32', o._tunnel.OutboundVcLabel)
   end
   if o._tunnel.InboundVcLabel ~= nil then
      mib:register('cpwVcInboundVcLabel', 'Unsigned32', o._tunnel.InboundVcLabel)
   end
   mib:register('cpwVcName', 'OctetStr', conf.interface)
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
   mib:register('_X_pwEnetPortIfIndex', 'OctetStr', conf.interface)
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
   mib:register('_X_cpwVcEnetPortIfIndex', 'OctetStr', conf.interface)
   mib:register('cpwVcEnetVcIfIndex', 'Integer32', 0) -- PW not modelled as ifIndex
   mib:register('cpwVcEnetRowStatus', 'Integer32', 1) -- active
   mib:register('cpwVcEnetStorageType', 'Integer32', 2) -- volatile

   o._mib = mib

   -- Set up the control channel
   if have_cc then
      local c = conf.cc
      for k, v in pairs(cc_defaults) do
         if c[k] == nil then
            c[k] = v
         end
      end

      -- -- Create a static packet to transmit on the control channel
      local dgram = datagram:new(packet.allocate())
      dgram:push(o._tunnel.cc_header)
      dgram:push(o._transport.header)
      dgram:push(o._ether)
      cc.add_tlv(dgram, 'heartbeat', c.heartbeat)
      cc.add_tlv(dgram, 'mtu', conf.mtu)
      -- The if_description ends up in the
      -- pwRemoteIfString/cpwVCRemoteIfString MIB objects.  The
      -- CISCO-IETF-PW-MIB refers to this value as the "interface's
      -- name as appears on the ifTable".  The STD-PW-MIB is more
      -- specific and defines the value to be sent to be the ifAlias
      -- of the local interface.
      cc.add_tlv(dgram, 'if_description', conf.name)
      cc.add_tlv(dgram, 'vc_id', conf.vc_id)
      -- Set the IPv6 payload length
      dgram:new(dgram:packet(), ethernet)
      local cc_ipv6 = dgram:parse_n(2)
      local _, p_length = dgram:payload()
      cc_ipv6:payload_length(p_length)
      dgram:unparse(2) -- Free parsed protos
      o._cc = {}

      -- Set up control-channel processing
      o._cc.timer_xmit = timer.new("pw "..conf.name.." control-channel xmit",
                                   function (t)
                                      link.transmit(o.output.uplink,
                                                    packet.clone(dgram:packet()))
                                   end,
                                   1e9 * c.heartbeat, 'repeating')
      o._cc.timer_hb = timer.new("pw "..conf.name.." control-channel heartbeat",
                                 function(t)
                                    if mib:get('cpwVcInboundOperStatus') == 1 then
                                       local now = math.floor(tonumber(C.get_time_ns())/1e9)
                                       local diff = now - o._cc.rcv_tstamp
                                       local hb = o._cc.remote_hb
                                       if diff > hb then
                                          log(o, "Missed remote heartbeat, dead in "
                                              ..(hb*(c.dead_factor+1)-diff).." seconds", true)
                                       end
                                       if diff > hb * c.dead_factor then
                                          log(o, "Peer declared dead", true)
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

   -- Packet pointer cache to avoid cdata allocation in the push()
   -- loop
   o._p = ffi.new("struct packet *[1]")
   return o
end

local full, empty, receive, transmit = link.full, link.empty, link.receive, link.transmit
function pseudowire:push()
   local l_in = self.input.ac
   local l_out = self.output.uplink
   local p = self._p
   while not full(l_out) and not empty(l_in) do
      p[0] = receive(l_in)
      if self._cc and not self._forward then
         -- The PW is marked non-functional by the control channel,
         -- discard packet
         packet.free(p[0])
         return
      end
      local datagram = self._dgram:new(p[0], ethernet)
      -- Perform actions on transport and tunnel headers required for
      -- encapsulation
      self._transport:encapsulate(datagram, self._tunnel.header)
      self._tunnel:encapsulate(datagram)

      -- Copy the finished headers into the packet
      datagram:push_raw(self._template:data())
      transmit(l_out, datagram:packet())
   end

   l_in = self.input.uplink
   l_out = self.output.ac
   while not full(l_out) and not empty(l_in) do
      p[0] = receive(l_in)
      local datagram = self._dgram:new(p[0], ethernet, dgram_options)
      if self._filter:match(datagram:payload()) then
         datagram:pop_raw(self._decap_header_size, self._tunnel.class)
         local status, code = self._tunnel:decapsulate(datagram)
         if status == true then
            datagram:commit()
            transmit(l_out, datagram:packet())
         else
            if code == 0 then
               increment_errors(self)
            elseif code == 1 then
               process_cc(self, datagram)
            end
            packet.free(p[0])
         end
      else
         packet.free(datagram:packet())
      end
   end
end

local function selftest_aux(type, pseudowire_config, local_mac, remote_mac)
   local c = config.new()
   local pcap_base = "program/l2vpn/selftest/"
   local pcap_type = pcap_base..type
   local nd_light = require("apps.ipv6.nd_light").nd_light
   config.app(c, "nd", nd_light,
              { local_mac = local_mac,
                remote_mac = remote_mac,
                local_ip = "::",
                next_hop = "::" })
   config.app(c, "from_uplink", pcap.PcapReader, pcap_type.."-uplink.cap.input")
   config.app(c, "from_ac", pcap.PcapReader, pcap_base.."ac.cap.input")
   config.app(c, "to_ac", pcap.PcapWriter, pcap_type.."-ac.cap.output")
   config.app(c, "to_uplink", pcap.PcapWriter, pcap_type.."-uplink.cap.output")
   config.app(c, "pw", pseudowire, pseudowire_config)

   config.link(c, "from_uplink.output -> nd.south")
   config.link(c, "nd.north -> pw.uplink")
   config.link(c, "pw.ac -> to_ac.input")
   config.link(c, "from_ac.output -> pw.ac")
   config.link(c, "pw.uplink -> nd.north")
   config.link(c, "nd.south -> to_uplink.input")
   app.configure(c)
   app.main({duration = 1})
   local ok = true
   if (io.open(pcap_type.."-ac.cap.output"):read('*a') ~=
       io.open(pcap_type.."-ac.cap.expect"):read('*a')) then
      print('tunnel '..type..' decapsulation selftest failed.')
      ok = false
   end
   if (io.open(pcap_type.."-uplink.cap.output"):read('*a') ~=
       io.open(pcap_type.."-uplink.cap.expect"):read('*a')) then
      print('tunnel '..type..' encapsulation selftest failed.')
      ok = false
   end
   if not ok then os.exit(1) end
   app.configure(config.new())
end

function selftest()
   local local_mac     = "90:e2:ba:62:86:e5"
   local remote_mac    = "28:94:0f:fd:49:40"
   local local_ip      = "2001:620:0:C101:0:0:0:2"
   local local_vpn_ip  = "2001:620:0:C000:0:0:0:FC"
   local remote_vpn_ip = "2001:620:0:C000:0:0:0:FE"
   local config = { name          = "pw",
                    vc_id         = 1,
                    mtu           = 1500,
                    shmem_dir     = "/tmp",
                    ethernet = { src = local_mac,
                                 dst = remote_mac },
                    transport = { type = 'ipv6',
                                  src = local_vpn_ip,
                                  dst = remote_vpn_ip },
                    tunnel = { type = 'gre',
                               checksum = true,
                               key = 0x12345678 } }
   selftest_aux('gre', config, local_mac, remote_mac)
   config.tunnel = { type = 'l2tpv3',
                     local_session = 0x11111111,
                     remote_session = 0x22222222,
                     local_cookie  = '\x00\x11\x22\x33\x44\x55\x66\x77',
                     remote_cookie = '\x88\x99\xaa\xbb\xcc\xdd\xee\xff' }
   selftest_aux('l2tpv3', config, local_mac, remote_mac)
end
