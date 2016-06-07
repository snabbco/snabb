-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Application to connect to a virtio-net driver implementation
--
-- Licensed under the Apache 2.0 license
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Copyright (c) 2015 Virtual Open Systems
--

module(..., package.seeall)

local debug = _G.developer_debug

local ffi       = require("ffi")
local C         = ffi.C
local S         = require('syscall')
local pci       = require("lib.hardware.pci")
local lib       = require("core.lib")
local bit       = require('bit')
local virtq     = require('lib.virtio.virtq_driver')
local VirtioPci = require('lib.virtio.virtio_pci').VirtioPci
local checksum  = require('lib.checksum')

local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift
local prepare_packet4, prepare_packet6 = checksum.prepare_packet4, checksum.prepare_packet6
local new_packet, free = packet.allocate, packet.free

-- constants
local ETHERTYPE_IPv4 = C.htons(0x0800)
local ETHERTYPE_IPv6 = C.htons(0x86DD)
local ETHERTYPE_OFF = 12
local ETHERLEN = 14 -- DST MAC | SRC MAC | ethertype
local VIRTIO_NET_HDR_F_NEEDS_CSUM = 1

local min_features = C.VIRTIO_NET_F_CSUM +
   C.VIRTIO_F_ANY_LAYOUT +
   C.VIRTIO_NET_F_CTRL_VQ
local want_features =  min_features

local RXQ = 0
local TXQ = 1

VirtioNetDriver = {}
VirtioNetDriver.__index = VirtioNetDriver

function VirtioNetDriver:new(args)

   local virtio_pci = VirtioPci:new(args.pciaddr)

   self.min_features = min_features
   self.want_features = want_features

   if args.use_checksum then
      self.transmit = self._transmit_checksum
   else
      self.transmit = self._transmit
   end

   virtio_pci:reset()
   virtio_pci:acknowledge()

   virtio_pci:driver()

   local error = virtio_pci:set_guest_features(self.min_features, self.want_features)
   if error then
      virtio_pci:free()
      return nil, error
   end

   if debug then print("enumerating queues...") end
   local vqs = {}
   for n = 0, 1 do
      local queue_num = virtio_pci:get_queue_num(n)
      if not queue_num then
         virtio_pci:failed()
         virtio_pci:free()
         return nil, "missing required virtqueues"
      end
      vqs[n] = virtq.allocate_virtq(queue_num)
      virtio_pci:set_queue_vring(n, vqs[n].vring_physaddr)
   end

   virtio_pci:driver_ok()

   return setmetatable({
      virtio_pci = virtio_pci,
      vqs = vqs,
   }, self)
end

function VirtioNetDriver:close()
   for n, _ in ipairs(self.vqs) do
      self.virtio_pci:disable_queue(n)
   end
   self.virtio_pci:free()
end

-- Device operation
function VirtioNetDriver:can_transmit()
   local txq = self.vqs[TXQ]
   return txq:can_add()
end

function VirtioNetDriver:_transmit_checksum(p)

   local ethertype = ffi.cast('uint16_t*', p.data + ETHERTYPE_OFF)[0]
   local l3p, l3len = p.data + ETHERLEN, p.length - ETHERLEN
   local csum_start, csum_off

   if ethertype == ETHERTYPE_IPv4 then
      csum_start, csum_off = prepare_packet4(l3p, l3len)
   elseif ethertype == ETHERTYPE_IPv6 then
      csum_start, csum_off = prepare_packet6(l3p, l3len)
   end

   if csum_start ~= nil then
      local flags = VIRTIO_NET_HDR_F_NEEDS_CSUM
      csum_start = csum_start + ETHERLEN
      self.vqs[TXQ]:add(p, p.length, flags, csum_start, csum_off)
   else
      self.vqs[TXQ]:add_empty_header(p, p.length)
   end

end

function VirtioNetDriver:_transmit(p)
   self.vqs[TXQ]:add_empty_header(p, p.length)
end

function VirtioNetDriver:sync_transmit()
   local txq = self.vqs[TXQ]

   txq:update_avail_idx()
end

function VirtioNetDriver:notify_transmit()
   local txq = self.vqs[TXQ]

   -- Notify the device if needed
   if txq:should_notify() then
      self.virtio_pci:notify_queue(TXQ)
   end
end

function VirtioNetDriver:recycle_transmit_buffers()
   local txq = self.vqs[TXQ]
   local to_free = txq:can_get()

   for i=0, to_free - 1 do
      local p = txq:get()
      free(p)
   end
end

function VirtioNetDriver:can_receive()
   local rxq = self.vqs[RXQ]
   return rxq:can_get()
end

function VirtioNetDriver:receive()
   return self.vqs[RXQ]:get()
end

function VirtioNetDriver:add_receive_buffers()
   local rxq = self.vqs[RXQ]
   local to_add = rxq:can_add()
   if to_add  == 0 then return end

   for i=0, to_add - 1 do
      rxq:add_empty_header(new_packet(), C.PACKET_PAYLOAD_SIZE)
   end

   rxq:update_avail_idx()
end

