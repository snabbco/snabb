--go@ git up
--- Device driver for the Mellanox ConnectX-4 series Ethernet controller.

-- This driver is written using these main reference sources:
-- 
--   PRM: Mellanox Adapter Programmer's Reference Manual
--        This document will be made available on Mellanox's website.
--        Has not happened yet (as of 2016-05-24).
--
--   mlx5_core: Linux kernel driver for ConnectX-4. This has been
--        developed by Mellanox.
--
--   Hexdumps: The Linux kernel driver has the capability to run in
--        debug mode and to output hexdumps showing the exact
--        interactions with the card. This driver has a similar
--        capability. This makes it possible to directly compare
--        driver behavior directly via hexdumps i.e. independently of
--        the source code.

-- Implementation notes:
--
--   RESET: This driver performs a PCIe reset of the device prior to
--        initialization. This is instead of performing the software
--        deinitialization procedure. The main reason for this is
--        simplicity and keeping the code minimal.
--
--        Relatedly, reloading the mlx5_core driver in Linux 4.4.8
--        does not seem to consistently succeed in reinitializing the
--        device. This may be due to bugs in the driver and/or firmware. 
--        Skipping the soft-reset would seem to reduce our driver's
--        exposure to such problems.
--
--        In the future we could consider implementing the software
--        reset if this is found to be important for some purpose.
--
--   SIGNATURE:
--        Command signatures fields: Are they useful? Are they used?
--
--        Usefulness - command signature is an 8-bit value calculated
--        with a simple xor. What does this protect and how effective
--        is it? Curious because PCIe is already performing a more
--        robust checksum. Perhaps the signature is designed to catch
--        driver bugs? Or host memory corruption? Enquiring minds
--        would like to know...
--
--        Used - the Linux driver has code for signatures but seems to
--        hard-code this as disabled at least in certain instances.
--        Likewise the card is accepting at least some commands from
--        this driver without signatures. It seems potentially futile
--        to calculate and include command signatures if they are not
--        actually being verified by the device.

module(...,package.seeall)

local ffi      = require "ffi"
local C        = ffi.C
local lib      = require("core.lib")
local pci      = require("lib.hardware.pci")
local register = require("lib.hardware.register")
local index_set = require("lib.index_set")
local macaddress = require("lib.macaddress")
local mib = require("lib.ipc.shmem.mib")
local timer = require("core.timer")
local bits, bitset = lib.bits, lib.bitset
local floor = math.floor
local cast = ffi.cast
local band, bor, shl, shr, bswap, bnot =
   bit.band, bit.bor, bit.lshift, bit.rshift, bit.bswap, bit.bnot

local debug = false

ConnectX4 = {}
ConnectX4.__index = ConnectX4

--utils

local function alloc_pages(pages)
   local ptr, phy = memory.dma_alloc(4096 * pages, 4096)
   assert(band(phy, 0xfff) == 0) --the phy address must be 4K-aligned
   return cast('uint32_t*', ptr), phy
end

function getint(addr, ofs)
   local ofs = ofs/4
   assert(ofs == floor(ofs))
   return bswap(addr[ofs])
end

function setint(addr, ofs, val)
   local ofs = ofs/4
   assert(ofs == floor(ofs))
   addr[ofs] = bswap(tonumber(val))
end

local function getbits(val, bit2, bit1)
   local mask = shl(2^(bit2-bit1+1)-1, bit1)
   return shr(band(val, mask), bit1)
end

local function ptrbits(ptr, bit2, bit1)
   local addr = cast('uint64_t', ptr)
   return tonumber(getbits(addr, bit2, bit1))
end

local function setbits1(bit2, bit1, val)
   local mask = shl(2^(bit2-bit1+1)-1, bit1)
   local bits = band(shl(val, bit1), mask)
   return bits
end

local function setbits(...) --bit2, bit1, val, ...
   local endval = 0
   for i = 1, select('#', ...), 3 do
      local bit2, bit1, val = select(i, ...)
      endval = bor(endval, setbits1(bit2, bit1, val or 0))
   end
   return endval
end


--init segment (section 4.3)

local init_seg = {}
init_seg.__index = init_seg

function init_seg:getbits(ofs, bit2, bit1)
   return getbits(getint(self.ptr, ofs), bit2, bit1)
end

function init_seg:setbits(ofs, ...)
   setint(self.ptr, ofs, setbits(...))
end

function init_seg:init(ptr)
   return setmetatable({ptr = cast('uint32_t*', ptr)}, self)
end

function init_seg:fw_rev() --maj, min, subminor
   return
      self:getbits(0, 15, 0),
      self:getbits(0, 31, 16),
      self:getbits(4, 15, 0)
end

function init_seg:cmd_interface_rev()
   return self:getbits(4, 31, 16)
end

function init_seg:cmdq_phy_addr(addr)
   if addr then
      --must write the MSB of the addr first
      self:setbits(0x10, 31, 0, ptrbits(addr, 63, 32))
      --also resets nic_interface and log_cmdq_*
      self:setbits(0x14, 31, 12, ptrbits(addr, 31, 12))
   else
      return cast('void*',
         cast('uint64_t', self:getbits(0x10, 31, 0) * 2^32 +
         cast('uint64_t', self:getbits(0x14, 31, 12)) * 2^12))
   end
end

function init_seg:nic_interface(mode)
   self:setbits(0x14, 9, 8, mode)
end

function init_seg:log_cmdq_size()
   return self:getbits(0x14, 7, 4)
end

function init_seg:log_cmdq_stride()
   return self:getbits(0x14, 3, 0)
end

function init_seg:ring_doorbell(i)
   self:setbits(0x18, i, i, 1)
end

function init_seg:ready(i, val)
   return self:getbits(0x1fc, 31, 31) == 0
end

function init_seg:nic_interface_supported()
   return self:getbits(0x1fc, 26, 24) == 0
end

function init_seg:internal_timer()
   return
      self:getbits(0x1000, 31, 0) * 2^32 +
      self:getbits(0x1004, 31, 0)
end

function init_seg:clear_int()
   self:setbits(0x100c, 0, 0, 1)
end

function init_seg:health_syndrome()
   return self:getbits(0x1010, 31, 24)
end

--command queue (section 7.14.1)

local cmdq = {}
cmdq.__index = cmdq

--init cmds
local QUERY_HCA_CAP      = 0x100
local QUERY_ADAPTER      = 0x101
local INIT_HCA           = 0x102
local TEARDOWN_HCA       = 0x103
local ENABLE_HCA         = 0x104
local DISABLE_HCA        = 0x105
local QUERY_PAGES        = 0x107
local MANAGE_PAGES       = 0x108
local SET_HCA_CAP        = 0x109
local QUERY_ISSI         = 0x10A
--local QUERY_ISSI         = 0x010A
--local QUERY_ISSI         = 0x0A01
local SET_ISSI           = 0x10B
local SET_DRIVER_VERSION = 0x10D

-- bytewise xor function used for signature calcuation.
local function xor8 (ptr, len)
   local u8 = ffi.cast("uint8_t*", ptr)
   local acc = 0
   for i = 0, len-1 do
      acc = bit.bxor(acc, u8[i])
   end
   return acc
end

local cmdq_entry_t   = ffi.typeof("uint32_t[0x40/4]")
local cmdq_mailbox_t = ffi.typeof("uint32_t[0x240/4]")

-- XXX Check with maximum length of commands that we really use.
local max_mailboxes = 1000
local data_per_mailbox = 0x200 -- Bytes of input/output data in a mailbox

-- Create a command queue with dedicated/reusable DMA memory.
function cmdq:new(init_seg)
   local entry = ffi.cast("uint32_t*", memory.dma_alloc(0x40))
   local inboxes, outboxes = {}, {}
   for i = 0, max_mailboxes-1 do
      -- XXX overpadding.. 0x240 alignment is not accepted?
      inboxes[i]  = ffi.cast("uint32_t*", memory.dma_alloc(0x240, 4096))
      outboxes[i] = ffi.cast("uint32_t*", memory.dma_alloc(0x240, 4096))
   end
   return setmetatable({entry = entry,
                        inboxes = inboxes,
                        outboxes = outboxes,
                        init_seg = init_seg,
                        size = init_seg:log_cmdq_size(),
                        stride = init_seg:log_cmdq_stride()},
      self)
end

-- Reset all data structures to zero values.
-- This is to prevent leakage from one command to the next.
local token = 0xAA
function cmdq:prepare(command, last_input_offset, last_output_offset)
   print("Command: " .. command)
   local input_size  = last_input_offset + 4
   local output_size = last_output_offset + 4

   -- Command entry:

   ffi.fill(self.entry, ffi.sizeof(cmdq_entry_t), 0)
   self:setbits(0x00, 31, 24, 0x7)        -- type
   self:setbits(0x04, 31, 0, input_size)
   self:setbits(0x38, 31, 0, output_size)
   self:setbits(0x3C,
                0, 0, 1, -- ownership = hardware
                31, 24, token)

   -- Mailboxes:

   -- How many mailboxes do we need?
   local ninboxes  = math.ceil((input_size  - 16) / data_per_mailbox)
   local noutboxes = math.ceil((output_size - 16) / data_per_mailbox)
   if ninboxes  > max_mailboxes then error("Input overflow: " ..input_size)  end
   if noutboxes > max_mailboxes then error("Output overflow: "..output_size) end

   if ninboxes > 0 then
      local phy = memory.virtual_to_physical(self.inboxes[0])
      setint(self.entry, 0x08, phy / 2^32)
      setint(self.entry, 0x0C, phy % 2^32)
   end
   if noutboxes > 0 then
      local phy = memory.virtual_to_physical(self.outboxes[0])
      setint(self.entry, 0x30, phy / 2^32)
      setint(self.entry, 0x34, phy % 2^32)
   end

   -- Initialize mailboxes
   for i = 0, max_mailboxes-1 do
      -- Zap old state
      ffi.fill(self.inboxes[i],  ffi.sizeof(cmdq_mailbox_t), 0)
      ffi.fill(self.outboxes[i], ffi.sizeof(cmdq_mailbox_t), 0)
      -- Set mailbox block number
      setint(self.inboxes[i],  0x238, i)
      setint(self.outboxes[i], 0x238, i)
      -- Tokens to match command entry
      setint(self.inboxes[i],  0x23C, setbits(23, 16, token))
      setint(self.outboxes[i], 0x23C, setbits(23, 16, token))
      -- Set 'next' mailbox pointers (when used)
      if i < ninboxes then
         local phy = memory.virtual_to_physical(self.inboxes[i+1])
         setint(self.inboxes[i], 0x230, phy / 2^32)
         setint(self.inboxes[i], 0x234, phy % 2^32)
      end
      if i < noutboxes then
         local phy = memory.virtual_to_physical(self.outboxes[i+1])
         setint(self.outboxes[i], 0x230, phy / 2^32)
         setint(self.outboxes[i], 0x234, phy % 2^32)
      end
   end
   token = (token == 255) and 1 or token+1
end

function cmdq:getbits(ofs, bit2, bit1)
   return getbits(getint(self.entry, ofs), bit2, bit1)
end

function cmdq:setbits(ofs, ...)
   setint(self.entry, ofs, setbits(...))
end

function cmdq:setinbits(ofs, ...) --bit1, bit2, val, ...
   assert(ofs % 4 == 0)
   if ofs <= 16 - 4 then --inline
      self:setbits(0x10 + ofs, ...)
   else --input mailbox
      local mailbox = math.floor((ofs - 16) / data_per_mailbox)
      local offset = (ofs - 16) % data_per_mailbox
      setint(self.inboxes[mailbox], offset, setbits(...))
   end
end

function cmdq:getoutbits(ofs, bit2, bit1)
   if ofs <= 16 - 4 then --inline
      return self:getbits(0x20 + ofs, bit2, bit1)
   else --output mailbox
      local mailbox = math.floor((ofs - 16) / data_per_mailbox)
      local offset  = (ofs - 16) % data_per_mailbox
      local b = getbits(getint(self.outboxes[mailbox], offset), bit2, bit1)
      return b
   end
end

-- "Command delivery status" error codes.
local delivery_errors = {
   [0x00] = 'no errors',
   [0x01] = 'signature error',
   [0x02] = 'token error',
   [0x03] = 'bad block number',
   [0x04] = 'bad output pointer. pointer not aligned to mailbox size',
   [0x05] = 'bad input pointer. pointer not aligned to mailbox size',
   [0x06] = 'internal error',
   [0x07] = 'input len error. input length less than 0x8',
   [0x08] = 'output len error. output length less than 0x8',
   [0x09] = 'reserved not zero',
   [0x10] = 'bad command type',
   -- Note: Suspicious to jump from 0x09 to 0x10 here i.e. skipping 0x0A - 0x0F.
   --       This is consistent with both the PRM and the Linux mlx5_core driver.
}

local function checkz(z)
   if z == 0 then return end
   error('command error: '..(delivery_errors[z] or z))
end

-- Command error code meanings.
-- Note: This information is missing from the PRM. Can compare with Linux mlx5_core.
local command_errors = {
   -- General:
   [0x01] = 'INTERNAL_ERR: internal error',
   [0x02] = 'BAD_OP: Operation/command not supported or opcode modifier not supported',
   [0x03] = 'BAD_PARAM: parameter not supported; parameter out of range; reserved not equal 0',
   [0x04] = 'BAD_SYS_STATE: System was not enabled or bad system state',
   [0x05] = 'BAD_RESOURCE: Attempt to access reserved or unallocated resource, or resource in inappropriate status. for example., not existing CQ when creating QP',
   [0x06] = 'RESOURCE_BUSY: Requested resource is currently executing a command. No change in any resource status or state i.e. command just not executed.',
   [0x08] = 'EXCEED_LIM: Required capability exceeds device limits',
   [0x09] = 'BAD_RES_STATE: Resource is not in the appropriate state or ownership',
   [0x0F] = 'NO_RESOURCES: Command was not executed because lack of resources (for example ICM pages). This is unrecoverable situation from driver point of view',
   [0x50] = 'BAD_INPUT_LEN: Bad command input len',
   [0x51] = 'BAD_OUTPUT_LEN: Bad command output len',
   -- QP/RQ/SQ/TIP:
   [0x10] = 'BAD_RESOURCE_STATE: Attempt to modify a Resource (RQ/SQ/TIP/QPs) which is not in the presumed state',
   -- MAD:
   [0x30] = 'BAD_PKT: Bad management packet (silently discarded)',
   -- CQ:
   [0x40] = 'BAD_SIZE: More outstanding CQEs in CQ than new CQ size',
}

function cmdq:post(last_in_ofs, last_out_ofs)
   if debug then
      local dumpoffset = 0
      print("command INPUT:")
      dumpoffset = hexdump(self.entry, 0, 0x40, dumpoffset)
      local ninboxes  = math.ceil((last_in_ofs + 4 - 16) / data_per_mailbox)
      for i = 0, ninboxes-1 do
         local blocknumber = getint(self.inboxes[i], 0x238, 31, 0)
         local address = memory.virtual_to_physical(self.inboxes[i])
         print("Block "..blocknumber.." @ "..bit.tohex(address, 12)..":")
         dumpoffset = hexdump(self.inboxes[i], 0, ffi.sizeof(cmdq_mailbox_t), dumpoffset)
      end
   end

   self.init_seg:ring_doorbell(0) --post command

   --poll for command completion
   while self:getbits(0x3C, 0, 0) == 1 do
      C.usleep(100000)
   end

   if debug then
      local dumpoffset = 0
      print("command OUTPUT:")
      dumpoffset = hexdump(self.entry, 0, 0x40, dumpoffset)
      local noutboxes = math.ceil((last_out_ofs + 4 - 16) / data_per_mailbox)
      for i = 0, noutboxes-1 do
         local blocknumber = getint(self.outboxes[i], 0x238, 31, 0)
         local address = memory.virtual_to_physical(self.outboxes[i])
         print("Block "..blocknumber.." @ "..bit.tohex(address, 12)..":")
         dumpoffset = hexdump(self.outboxes[i], 0, ffi.sizeof(cmdq_mailbox_t), dumpoffset)
      end
   end

   local token     = self:getbits(0x3C, 31, 24)
   local signature = self:getbits(0x3C, 23, 16)
   local status    = self:getbits(0x3C,  7,  1)

   checkz(status)
   self:checkstatus()

   return signature, token
end

-- see 12.2 Return Status Summary
function cmdq:checkstatus()
   local status = self:getoutbits(0x00, 31, 24)
   local syndrome = self:getoutbits(0x04, 31, 0)
   if status == 0 then return end
   error(string.format('status: 0x%x (%s), syndrome: %d',
                       status, command_errors[status], syndrome))
end

function cmdq:enable_hca()
   self:prepare("ENABLE_HCA", 0x0C, 0x08)
   self:setinbits(0x00, 31, 16, ENABLE_HCA)
   self:post(0x0C, 0x08)
end

function cmdq:query_issi()
   self:prepare("QUERY_ISSI", 0x0C, 0x6C)
   self:setinbits(0x00, 31, 16, QUERY_ISSI)
   self:post(0x0C, 0x6C)
   local cur_issi = self:getoutbits(0x08, 15, 0)
   local t = {}
   for i = 639, 0, -1 do
      -- Bit N (0..639) when set means ISSI version N is enabled.
      -- Bits are ordered from highest to lowest.
      local byte = 0x20 + math.floor(i / 8)
      local offset = byte - (byte % 4)
      local bit = 31 - (i % 32)
      if self:getoutbits(offset, bit, bit) == 1 then
         local issi = 639 - i
         t[issi] = true
      end
   end
   return {
      cur_issi = cur_issi,
      sup_issi = t,
   }
end

function cmdq:set_issi(issi)
   self:reset()
   self:setinbits(0x00, 31, 16, SET_ISSI)
   self:setinbits(0x08, 15, 0, issi)
   self:post(0x0C, 0x0C)
end

function cmdq:dump_issi(issi)
   print('  cur_issi            = ', issi.cur_issi)
   print('  sup_issi            = ')
   for i=0,79 do
      if issi.sup_issi[i] then
   print(string.format(
         '     %02d               ', i))
      end
   end
end

local codes = {
   boot = 1,
   init = 2,
   regular = 3,
}
function cmdq:query_pages(which)
   self:prepare("QUERY_PAGES", 0x0C, 0x0C)
   self:setinbits(0x00, 31, 16, QUERY_PAGES)
   self:setinbits(0x04, 15, 0, codes[which])
   self:post(0x0C, 0x0C)
   return self:getoutbits(0x0C, 31, 0)
end

function cmdq:alloc_pages(addr, num_pages)
   self:prepare("MANAGE_PAGES", 0x10 + num_pages*8, 0x0C)
   self:setinbits(0x00, 31, 16, MANAGE_PAGES)
   self:setinbits(0x04, 15, 0, 1) --alloc
   self:setinbits(0x0C, 31, 0, num_pages)
   local addr = cast('char*', addr)
   for i=0, num_pages-1 do
      self:setinbits(0x10 + i*8, 31,  0, ptrbits(addr + 4096*i, 63, 32))
      self:setinbits(0x14 + i*8, 31, 12, ptrbits(addr + 4096*i, 31, 12))
   end
   self:post(0x10 + num_pages*8, 0x0C)
end

local what_codes = {
   max = 0,
   cur = 1,
}
local which_codes = {
   general = 0,
   offload = 1,
   flow_table = 7,
}
function cmdq:query_hca_cap(what, which)
   self:prepare("QUERY_HCA_CAP", 0x0C, 0x100C - 3000)
   self:setinbits(0x00, 31, 16, QUERY_HCA_CAP)
   self:setinbits(0x04,
      15,  1, assert(which_codes[which]),
       0,  0, assert(what_codes[what]))
   self:post(0x0C, 0x100C - 3000)
   local caps = {}
   if which == 'general' then
      caps.log_max_cq_sz            = self:getoutbits(0x18, 23, 16)
      caps.log_max_cq               = self:getoutbits(0x18,  4,  0)
      caps.log_max_eq_sz            = self:getoutbits(0x1C, 31, 24)
      caps.log_max_mkey             = self:getoutbits(0x1C, 21, 16)
      caps.log_max_eq               = self:getoutbits(0x1C,  3,  0)
      caps.max_indirection          = self:getoutbits(0x20, 31, 24)
      caps.log_max_mrw_sz           = self:getoutbits(0x20, 22, 16)
      caps.log_max_klm_list_size    = self:getoutbits(0x20,  5,  0)
      caps.end_pad                  = self:getoutbits(0x2C, 31, 31)
      caps.start_pad                = self:getoutbits(0x2C, 28, 28)
      caps.cache_line_128byte       = self:getoutbits(0x2C, 27, 27)
      caps.vport_counters           = self:getoutbits(0x30, 30, 30)
      caps.vport_group_manager      = self:getoutbits(0x34, 31, 31)
      caps.nic_flow_table           = self:getoutbits(0x34, 25, 25)
      caps.port_type                = self:getoutbits(0x34,  9,  8)
      caps.num_ports                = self:getoutbits(0x34,  7,  0)
      caps.log_max_msg              = self:getoutbits(0x38, 28, 24)
      caps.max_tc                   = self:getoutbits(0x38, 19, 16)
      caps.cqe_version              = self:getoutbits(0x3C,  3,  0)
      caps.cmdif_checksum           = self:getoutbits(0x40, 15, 14)
      caps.wq_signature             = self:getoutbits(0x40, 11, 11)
      caps.sctr_data_cqe            = self:getoutbits(0x40, 10, 10)
      caps.eth_net_offloads         = self:getoutbits(0x40,  3,  3)
      caps.cq_oi                    = self:getoutbits(0x44, 31, 31)
      caps.cq_resize                = self:getoutbits(0x44, 30, 30)
      caps.cq_moderation            = self:getoutbits(0x44, 29, 29)
      caps.cq_eq_remap              = self:getoutbits(0x44, 25, 25)
      caps.scqe_break_moderation    = self:getoutbits(0x44, 21, 21)
      caps.cq_period_start_from_cqe = self:getoutbits(0x44, 20, 20)
      caps.imaicl                   = self:getoutbits(0x44, 14, 14)
      caps.xrc                      = self:getoutbits(0x44,  3,  3)
      caps.ud                       = self:getoutbits(0x44,  2,  2)
      caps.uc                       = self:getoutbits(0x44,  1,  1)
      caps.rc                       = self:getoutbits(0x44,  0,  0)
      caps.uar_sz                   = self:getoutbits(0x48, 21, 16)
      caps.log_pg_sz                = self:getoutbits(0x48,  7,  0)
      caps.bf                       = self:getoutbits(0x4C, 31, 31)
      caps.driver_version           = self:getoutbits(0x4C, 30, 30)
      caps.pad_tx_eth_packet        = self:getoutbits(0x4C, 29, 29)
      caps.log_bf_reg_size          = self:getoutbits(0x4C, 20, 16)
      caps.log_max_transport_domain = self:getoutbits(0x64, 28, 24)
      caps.log_max_pd               = self:getoutbits(0x64, 20, 16)
      caps.max_flow_counter         = self:getoutbits(0x68, 15,  0)
      caps.log_max_rq               = self:getoutbits(0x6C, 28, 24)
      caps.log_max_sq               = self:getoutbits(0x6C, 20, 16)
      caps.log_max_tir              = self:getoutbits(0x6C, 12,  8)
      caps.log_max_tis              = self:getoutbits(0x6C,  4,  0)
      caps.basic_cyclic_rcv_wqe     = self:getoutbits(0x70, 31, 31)
      caps.log_max_rmp              = self:getoutbits(0x70, 28, 24)
      caps.log_max_rqt              = self:getoutbits(0x70, 20, 16)
      caps.log_max_rqt_size         = self:getoutbits(0x70, 12,  8)
      caps.log_max_tis_per_sq       = self:getoutbits(0x70,  4,  0)
      caps.log_max_stride_sz_rq     = self:getoutbits(0x74, 28, 24)
      caps.log_min_stride_sz_rq     = self:getoutbits(0x74, 20, 16)
      caps.log_max_stride_sz_sq     = self:getoutbits(0x74, 12,  8)
      caps.log_min_stride_sz_sq     = self:getoutbits(0x74,  4,  0)
      caps.log_max_wq_sz            = self:getoutbits(0x78,  4,  0)
      caps.log_max_vlan_list        = self:getoutbits(0x7C, 20, 16)
      caps.log_max_current_mc_list  = self:getoutbits(0x7C, 12,  8)
      caps.log_max_current_uc_list  = self:getoutbits(0x7C,  4,  0)
      caps.log_max_l2_table         = self:getoutbits(0x90, 28, 24)
      caps.log_uar_page_sz          = self:getoutbits(0x90, 15,  0)
      caps.device_frequency_mhz     = self:getoutbits(0x98, 31,  0)
   elseif which_caps == 'offload' then
      --TODO
   elseif which_caps == 'flow_table' then
      --TODO
   end
   return caps
end

function cmdq:set_hca_cap(which, caps)
   self:prepare("SET_HCA_CAP", 0x100C, 0x0C)
   self:setinbits(0x00, 31, 16, SET_HCA_CAP)
   self:setinbits(0x04, 15,  1, assert(which_codes[which]))
   if which_caps == 'general' then
      self:setinbits(0x18,
         23, 16, caps.log_max_cq_sz,
         4,   0, caps.log_max_cq)
      self:setinbits(0x1C,
         31, 24, caps.log_max_eq_sz,
         21, 16, caps.log_max_mkey,
         3,   0, caps.log_max_eq)
      self:setinbits(0x20,
         31, 24, caps.max_indirection,
         22, 16, caps.log_max_mrw_sz,
         5,   0, caps.log_max_klm_list_size)
      self:setinbits(0x2C,
         31, 31, caps.end_pad,
         28, 28, caps.start_pad,
         27, 27, caps.cache_line_128byte)
      self:setinbits(0x30,
         30, 30, caps.vport_counters)
      self:setinbits(0x34,
         31, 31, caps.vport_group_manager,
         25, 25, caps.nic_flow_table,
          9,  8, caps.port_type,
          7,  0, caps.num_ports)
      self:setinbits(0x38,
         28, 24, caps.log_max_msg,
         19, 16, caps.max_tc)
      self:setinbits(0x3C,
          3,   0, caps.cqe_version)
      self:setinbits(0x40,
         15, 14, caps.cmdif_checksum,
         11, 11, caps.wq_signature,
         10, 10, caps.sctr_data_cqe,
          3,  3, caps.eth_net_offloads)
      self:setinbits(0x44,
         31, 31, caps.cq_oi,
         30, 30, caps.cq_resize,
         29, 29, caps.cq_moderation,
         25, 25, caps.cq_eq_remap,
         21, 21, caps.scqe_break_moderation,
         20, 20, caps.cq_period_start_from_cqe,
         14, 14, caps.imaicl,
          3,  3, caps.xrc,
          2,  2, caps.ud,
          1,  1, caps.uc,
          0,  0, caps.rc)
      self:setinbits(0x48,
         21, 16, caps.uar_sz,
          7,  0, caps.log_pg_sz)
      self:setinbits(0x4C,
         31, 31, caps.bf,
         30, 30, caps.driver_version,
         29, 29, caps.pad_tx_eth_packet,
         20, 16, caps.log_bf_reg_size)
      self:setinbits(0x64,
         28, 24, caps.log_max_transport_domain,
         20, 16, caps.log_max_pd)
      self:setinbits(0x68,
         15,  0, caps.max_flow_counter)
      self:setinbits(0x6C,
         28, 24, caps.log_max_rq,
         20, 16, caps.log_max_sq,
         12,  8, caps.log_max_tir,
          4,  0, caps.log_max_tis)
      self:setinbits(0x70,
         31, 31, caps.basic_cyclic_rcv_wqe,
         28, 24, caps.log_max_rmp,
         20, 16, caps.log_max_rqt,
         12,  8, caps.log_max_rqt_size,
          4,  0, caps.log_max_tis_per_sq)
      self:setinbits(0x74,
         28, 24, caps.log_max_stride_sz_rq,
         20, 16, caps.log_min_stride_sz_rq,
         12,  8, caps.log_max_stride_sz_sq,
          4,  0, caps.log_min_stride_sz_sq)
      self:setinbits(0x78,
          4,  0, caps.log_max_wq_sz)
      self:setinbits(0x7C,
         20, 16, caps.log_max_vlan_list,
         12,  8, caps.log_max_current_mc_list,
          4,  0, caps.log_max_current_uc_list)
      self:setinbits(0x90,
         28, 24, caps.log_max_l2_table,
         15,  0, caps.log_uar_page_sz)
      self:setinbits(0x98,
         31,  0, caps.device_frequency_mhz)
   elseif which_caps == 'offload' then
      self:setinbits(0x00,
         31, 31, caps.csum_cap,
         30, 30, caps.vlan_cap,
         29, 29, caps.lro_cap,
         28, 28, caps.lro_psh_flag,
         27, 27, caps.lro_time_stamp,
         26, 25, caps.lro_max_msg_sz_mode,
         23, 23, caps.self_lb_en_modifiable,
         22, 22, caps.self_lb_mc,
         21, 21, caps.self_lb_uc,
         20, 16, caps.max_lso_cap,
         13, 12, caps.wqe_inline_mode,
         11,  8, caps.rss_ind_tbl_cap)
      self:setinbits(0x08,
         15,  0, caps.lro_min_mss_size)
      for i = 1, 4 do
         self:setinbits(0x30 + (i-1)*4, 31, 0, caps.lro_timer_supported_periods[i])
      end
   elseif which_caps == 'flow_table' then
      --TODO
   end
   self:post(0x100C, 0x0C)
end

function cmdq:init_hca()
   self:prepare("INIT_HCA", 0x0c, 0x0c)
   self:setinbits(0x00, 31, 16, INIT_HCA)
   self:post(0x0C, 0x0C)
end

function init_seg:dump()
   print('fw_rev                  ', self:fw_rev())
   print('cmd_interface_rev       ', self:cmd_interface_rev())
   print('cmdq_phy_addr           ', self:cmdq_phy_addr())
   print('log_cmdq_size           ', self:log_cmdq_size())
   print('log_cmdq_stride         ', self:log_cmdq_stride())
   print('ready                   ', self:ready())
   print('nic_interface_supported ', self:nic_interface_supported())
   print('internal_timer          ', self:internal_timer())
   print('health_syndrome         ', self:health_syndrome())
end

function ConnectX4:new(arg)
   local self = setmetatable({}, self)
   local conf = config.parse_app_arg(arg)
   local pciaddress = pci.qualified(conf.pciaddress)

   -- Perform a hard reset of the device to bring it into a blank state.
   -- (PRM does not suggest this but it is practical for resetting the
   -- firmware from bad states.)
   pci.unbind_device_from_linux(pciaddress)
   pci.reset_device(pciaddress)
   pci.set_bus_master(pciaddress, true)
   local base, fd = pci.map_pci_memory(pciaddress, 0)

   trace("Read the initialization segment")
   local init_seg = init_seg:init(base)

   --allocate and set the command queue which also initializes the nic
   local cmdq = cmdq:new(init_seg)

   --8.2 HCA Driver Start-up

   trace("Write the physical location of the command queues to the init segment.")
   init_seg:cmdq_phy_addr(memory.virtual_to_physical(cmdq.entry))

   trace("Wait for the 'initializing' field to clear")
   while not init_seg:ready() do
      C.usleep(1000)
   end

   init_seg:dump()

   cmdq:enable_hca()
   local issi = cmdq:query_issi()
   cmdq:dump_issi(issi)

   --os.exit(0)
   --cmdq:set_issi(1)

   -- PRM: Execute QUERY_PAGES to understand the HCA need to boot pages.
   local boot_pages = cmdq:query_pages'boot'
   print("query_pages'boot'       ", boot_pages)
   assert(boot_pages > 0)

   -- PRM: Execute MANAGE_PAGES to provide the HCA with all required
   -- init-pages. This can be done by multiple MANAGE_PAGES commands.
   local bp_ptr, bp_phy = memory.dma_alloc(4096 * boot_pages, 4096)
   assert(band(bp_phy, 0xfff) == 0) --the phy address must be 4K-aligned
   cmdq:alloc_pages(bp_phy, boot_pages)

   local t = cmdq:query_hca_cap('cur', 'general')
   print'query_hca_cap (current, general):'
   for k,v in pairs(t) do
      print(("  %-24s = %s"):format(k, v))
   end

   local t = cmdq:query_hca_cap('max', 'general')
   print'query_hca_cap (maximum, general):'
   for k,v in pairs(t) do
      print(("  %-24s = %s"):format(k, v))
   end

   --[[
   cmdq:set_hca_cap()
   cmdq:query_pages()
   cmdq:manage_pages()
   cmdq:init_hca()
   cmdq:set_driver_version()
   cmdq:create_eq()
   cmdq:query_vport_state()
   cmdq:modify_vport_context()
   ]]

   function self:stop()
      pci.set_bus_master(pciaddress, false)
      pci.reset_device(pciaddress)
      pci.close_pci_resource(fd, base)
      base, fd = nil
   end

   return self
end

-- Print a hexdump in the same format as the Linux kernel.
-- 
-- Optionally take a 'dumpoffset' giving the logical address where the
-- trace starts (useful when printing multiple related hexdumps i.e.
-- for consistency with the Linux mlx5_core driver format).
function hexdump (pointer, index, bytes,  dumpoffset)
   local u8 = ffi.cast("uint8_t*", pointer)
   dumpoffset = dumpoffset or 0
   for i = 0, bytes-1 do
      if i % 16 == 0 then
         if i > 0 then io.stdout:write("\n") end
         io.stdout:write(("%03x: "):format(dumpoffset+i))
      elseif i % 4 == 0 then
         io.stdout:write(" ")
      end
      io.stdout:write(bit.tohex(u8[index+i], 2))
   end
   io.stdout:write("\n")
   io.flush()
   return dumpoffset + bytes
end

function trace (...)
   print("TRACE", ...)
end

function selftest()
   io.stdout:setvbuf'no'

   local pcidev = lib.getenv("SNABB_PCI_CONNECTX4_0")
   -- XXX check PCI device type
   if not pcidev then
      print("SNABB_PCI_CONNECTX4_0 not set")
      os.exit(engine.test_skipped_code)
   end

   local device_info = pci.device_info(pcidev)
   local app = ConnectX4:new{pciaddress = pcidev}
   app:stop()
end

