-- This module provides an in-band control-channel for a pseudowire.
-- It provides two types of services:
--
--   1. Parameter advertisement. One end of the PW can advertise local
--   parameters to its peer, either for informational purposes or to
--   detect misconfigurations.
--
--   2. Connection verification. Unidirectional connectivity is
--   verified by sending periodic heartbeat messages.  A monitoring
--   station that polls both endpoints can determine the full
--   connectivity status of the PW.
--
-- This proprietary protocol performs a subset of functions that are
-- provided by distinct protocols in standardised PW implementations
-- based on MPLS or L2TPv3.  Both of these provide a
-- "maintenance/signalling protocol" used to signal and set up a PW.
-- For MPLS, this role is played by LDP (in "targeted" mode).  For
-- L2TPv3, it is provided by a control-channel which is part of L2TPv3
-- itself (unless static configuration is used). The connection
-- verification is provided by another separate protocol called VCCV
-- (RFC5085).
--
-- VCCV requires a signalling protocol to be used in order to
-- negotiate the "CC" (control channel) and "CV" (connection
-- verification) modes to be used by the peers.  Currently, VCCV is
-- only specified for MPLS/LDP and L2TPv3, i.e. it is not possible to
-- implement it for either PW type provided by the current Snabb "vpn"
-- modules (i.e. GRE/IPv6 or L2TPv3 in "keyed IPv6" mode which does
-- not make use of the L2TPv3 control channel).
--
-- The simple control-channel protocol provided here uses a TLV
-- encoding to transmit information from one peer to the other.  The
-- data is carried in packets that use the same encapsulation as the
-- data traffic.  A protocol-dependent mechanism is used to
-- differentiate control traffic from data traffic as documented in
-- the apps/vpn/pseudowire module (i.e. a dedicated GRE key and L2TP
-- session ID, respectively).  The following TLVs are supported
--
--  - Heartbeat, type = 1, name = "heartbeat".  The value is an
--    unsigned 16-bit number that specifies the interval at which the
--    sender emits control frames.  It is used by the receiver to
--    determine whether it is reachable by the peer.
--
--  - MTU, type = 2, name = "mtu".  The MTU of the attachment circuit
--    (or virtual bridge port in case of a multi-point VPN) of the
--    sender.  The receiver should verify that it matches its own MTU
--    and should mark the PW as non-functional if this is not the
--    case.  The MTU is carried as an unsigned 16-bit number in the
--    TLV.
--
--  - Interface description, type = 3, name = "if_description".
--
--  - VC ID, type = 4, name = "vc_id".
--
-- This module only implements the construction and parsing of the
-- payload of a control-channel packet.  Construction of the entire
-- datagram as well as submission and reception of control-channel
-- packets is performed by the pseudowire module.
--
module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local datagram = require("lib.protocol.datagram")

ffi.cdef[[
      typedef struct {
         uint8_t type;
         uint8_t length;
      } tlv_h_t __attribute__((packed))
]]
local tlv_h_t = ffi.typeof("tlv_h_t")
local tlv_h_t_sizeof = ffi.sizeof(tlv_h_t)

--
-- API
--
-- Part of the types array is exposed to the user of the module.  It
-- is indexed by the type codes described above.  For each type, it
-- contains a ctype for the complete struct that makes up the TLV as
-- well as two accessor functions to get and set the value of the TLV.
-- The accessors take an instance of a pointer to the specific ctype
-- as input, e.g. as returned by the parse_next() iterator.
--
-- Types whose value is of variable length must also supply a function
-- that returns the length of the value in bytes (this is required by
-- add_tlv() to be able to determine the length of the TLV).
--
-- Any other fields apart from get, set and length are private to the
-- module and must not be accessed by the caller.
--
-- Caution: re-ordering of this table
-- will change the IDs of the protocol options.
--
types = {
   { name = "heartbeat",
     ct = ffi.typeof[[
           struct {
              tlv_h_t h;
              uint16_t value;
           } __attribute__((packed))]],
     get = function (tlv)
              return C.ntohs(tlv.value)
           end,
     set = function (tlv, value)
              tlv.value = C.htons(value)
           end
  },

   { name = "mtu",
     ct = ffi.typeof[[
           struct {
              tlv_h_t h;
              uint16_t value;
           }]],
     get = function (tlv)
              return C.ntohs(tlv.value)
           end,
     set = function (tlv, value)
              tlv.value = C.htons(value)
           end
  },

   { name = "if_description",
     ct = ffi.typeof[[
           struct {
              tlv_h_t h;
              char value[?];
           } __attribute__((packed))]],
     length = function (value)
                 return string.len(value)
              end,
     get = function (tlv)
              return ffi.string(tlv.value, tlv.h.length)
           end,
     set = function (tlv, value)
              ffi.copy(tlv.value, value, string.len(value))
           end
  },

   { name = "vc_id",
     ct = ffi.typeof[[
           struct {
              tlv_h_t h;
              uint32_t value;
           } __attribute__((packed))]],
     get = function (tlv)
              return C.ntohl(tlv.value)
           end,
     set = function (tlv, value)
              tlv.value = C.htonl(value)
           end
  },

}
local types_by_name = {}
for i, t in ipairs(types) do
   types[i].ct_ptr = ffi.typeof("$*", types[i].ct)
   types[i].id = i
   local n = types[i].name
   assert(types_by_name[n] == nil)
   types_by_name[n] = t
end

--
-- API
--
-- Create an invarant state to be used with the parse_next() iterator.
--
function create_state ()
   return { chunk = ffi.new("uint8_t *[1]"), len = 0 }
end

--
-- API
--
-- Iterator for traversing the TLV elements of a control-channel
-- packet.  The iterator returns two values.  The first is a pointer
-- to the next TLV object in a given chunk of data.  The second value
-- is either nil if the TLV was parsed successfully or a string that
-- describes the error that occured during parsing.  In the latter
-- case, the first value is merely a pointer to the TLV header,
-- i.e. the ctype object "tlv_h_t *".  Depending on the error, this
-- pointer is unsafe to de-reference.
--
-- Typical usage is as follows, where the datagram object contains the
-- control-channel packets with all headers parsed, i.e. the payload()
-- method returns the complete control-channel payload.
--
--   cc = require("apps.vpn.control_channel")
--   local state = cc.create_state()
--   state.chunk[0], state.len = datagram:payload()
--   for tlv, errmsg in cc.parse_next, state do
--     if errmsg then
--       -- Handle corrupt packet
--     else
--       -- Process TLV option
--       local type = cc.types[tlv.h.type]
--       local value = type.get(tlv)
--     end
--   done
--
function parse_next(state)
   local chunk, len = state.chunk[0], state.len
   if len == 0 then
      return nil, nil
   end
   len = len - tlv_h_t_sizeof
   local tlv_h = ffi.cast("tlv_h_t *", chunk)
   if len < tlv_h_t_sizeof then
      return tlv_h, "short packet while processing tlv header"
   end
   local type = types[tlv_h.type]
   if type == nil then
      return tlv_h, "unknown tlv type "..tlv_h.type
   end
   if tlv_h.length > len then
      return tlv_h, "short packet while processing tlv of type "..tlv_h.type
   end
   local tlv = ffi.cast(type.ct_ptr, chunk)
   state.len = len - tlv_h.length
   state.chunk[0] = chunk + tlv_h_t_sizeof + tlv_h.length
   return tlv, nil
end

function add_tlv (datagram, name, value)
   local type = types_by_name[name]
   assert(type, 'invalid type '..name)
   local len, tlv
   if type.length then
      len = type.length(value)
      tlv = type.ct(len)
   else
      tlv = type.ct()
      len = ffi.sizeof(tlv) - tlv_h_t_sizeof
   end
   tlv.h.type = type.id
   tlv.h.length = len
   type.set(tlv, value)
   datagram:payload(tlv, ffi.sizeof(tlv))
end

function selftest ()
   local dg = datagram:new()
   add_tlv(dg, 'mtu', 1500)
   add_tlv(dg, 'if_description', 'foobar')
   add_tlv(dg, 'heartbeat', 300)
   add_tlv(dg, 'vc_id', 1)

   local state = create_state()
   state.chunk[0], state.len = dg:payload()
   local tlv = parse_next(state)
   local type = types_by_name.mtu
   assert(tlv.h.type == type.id)
   assert(tlv.h.length == 2)
   assert(type.get(tlv) == 1500)

   tlv = parse_next(state)
   type = types_by_name.if_description
   assert(tlv.h.type == type.id)
   assert(tlv.h.length == 6)
   assert(type.get(tlv) == 'foobar')

   tlv = parse_next(state)
   type = types_by_name.heartbeat
   assert(tlv.h.type == type.id)
   assert(tlv.h.length == 2)
   assert(type.get(tlv) == 300)

   tlv = parse_next(state)
   type = types_by_name.vc_id
   assert(tlv.h.type == type.id)
   assert(tlv.h.length == 4)
   assert(type.get(tlv) == 1)

   tlv = parse_next(state)
   assert(tlv == nil)
end
