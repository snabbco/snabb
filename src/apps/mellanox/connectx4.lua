--go@ git up
--- Device driver for the Mellanox ConnectX-4 series Ethernet controller.

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

ConnectX4 = {}
ConnectX4.__index = ConnectX4

--utils

--alloc DMA memory in 4K-sized chunks and return an uint32 pointer
local function alloc_pages(pages)
   local ptr, phy = memory.dma_alloc(4096 * pages)
   assert(band(phy, 0xfff) == 0) --the phy address must be 4K-aligned
   return cast('uint32_t*', ptr), phy
end

--get an big-endian uint32 value from an uint32 pointer at a byte offset
function getint(addr, ofs)
   local ofs = ofs/4
   assert(ofs == floor(ofs))
   return bswap(addr[ofs])
end

--set a big-endian uint32 value into an uint32 pointer at a byte offset
function setint(addr, ofs, val)
   local ofs = ofs/4
   assert(ofs == floor(ofs))
   addr[ofs] = bswap(val)
end

--extract a bit range from a value
local function getbits(val, bit2, bit1)
   local mask = shl(2^(bit2-bit1+1)-1, bit1)
   return shr(band(val, mask), bit1)
end

--extract a bit range from a pointer
local function ptrbits(ptr, bit2, bit1)
   local addr = cast('uint64_t', ptr)
   return tonumber(getbits(addr, bit2, bit1))
end

--fit a value into a bit range and return the resulting value
local function setbits1(bit2, bit1, val)
   local mask = shl(2^(bit2-bit1+1)-1, bit1)
   return band(shl(val, bit1), mask)
end

--set multiple bit ranges and return the resulting value
local function setbits(...) --bit2, bit1, val, ...
   local endval = 0
   for i = 1, select('#', ...), 3 do
      local bit2, bit1, val = select(i, ...)
      endval = bor(endval, setbits1(bit2, bit1, val or 0))
   end
   return endval
end

--get the value of a bit at a certain a bit offset from a base address
local function getbit(addr, bit)
   local i = math.floor(bit / 32)
   local j = bit % 32
   return getbits(getint(addr, i * 4), j, j)
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
local SET_ISSI           = 0x10B
local SET_DRIVER_VERSION = 0x10D

function cmdq:new(init_seg)
   local ptr, phy = alloc_pages(1)
   local ib_ptr, ib_phy = alloc_pages(1)
   local ob_ptr, ob_phy = alloc_pages(1)
   return setmetatable({
      ptr = ptr,
      phy = phy,
      ib_ptr = ib_ptr,
      ob_ptr = ob_ptr,
      init_seg = init_seg,
      size = init_seg:log_cmdq_size(),
      stride = init_seg:log_cmdq_stride(),
   }, self)
end

function cmdq:getbits(ofs, bit2, bit1)
   return getbits(getint(self.ptr, ofs), bit2, bit1)
end

function cmdq:setbits(ofs, bit2, bit1, val)
   setint(self.ptr, ofs, setbits(bit2, bit1, val))
end

function cmdq:setinbits(ofs, ...) --bit1, bit2, val, ...
   assert(band(ofs, 3) == 0) --offset must be 4-byte aligned
   if ofs <= 16 - 4 then --inline
      self:setbits(0x10 + ofs, ...)
   else --input mailbox
      assert(ofs <= 16 - 4 + 4096)
      setint(self.ib_ptr, ofs, setbits(...))
   end
end

function cmdq:getoutbits(ofs, bit2, bit1)
   if ofs <= 16 - 4 then --inline
      return self:getbits(0x20 + ofs, bit2, bit1)
   else --output mailbox
      assert(ofs <= 16 - 4 + 4096)
      return getbits(getint(self.ob_ptr, ofs), bit2, bit1)
   end
end

function cmdq:getoutaddr(ofs)
   local ofs = (0x20 + ofs) / 4
   assert(ofs == math.floor(ofs))
   return self.ptr + ofs
end

function cmdq:getbit(ofs, bit)
   return getbit(self:getoutaddr(ofs), bit)
end

local errors = {
   'signature error',
   'token error',
   'bad block number',
   'bad output pointer. pointer not aligned to mailbox size',
   'bad input pointer. pointer not aligned to mailbox size',
   'internal error',
   'input len error. input length less than 0x8',
   'output len error. output length less than 0x8',
   'reserved not zero',
   'bad command type',
}
local function checkz(z)
   if z == 0 then return end
   error('command error: '..(errors[z] or z))
end

function cmdq:post(last_in_ofs, last_out_ofs)
   local in_sz  = last_in_ofs + 4
   local out_sz = last_out_ofs + 4

   self:setbits(0x00, 31, 24, 0x7) --type

   self:setbits(0x04, 31, 0, in_sz) --input_length
   self:setbits(0x38, 31, 0, out_sz) --output_length

   self:setbits(0x08, 31, 0, ptrbits(self.ib_addr, 63, 32))
   self:setbits(0x0C, 31, 9, ptrbits(self.ib_addr, 31, 9))

   self:setbits(0x30, 31, 0, ptrbits(self.ob_addr, 63, 32))
   self:setbits(0x34, 31, 9, ptrbits(self.ob_addr, 31, 9))

   self:setbits(0x3C, 0, 0, 1) --set ownership

   self.init_seg:ring_doorbell(0) --post command

   --poll for command completion
   while self:getbits(0x3C, 0, 0) == 1 do
      C.usleep(1000)
   end

   local token     = self:getbits(0x3C, 31, 24)
   local signature = self:getbits(0x3C, 23, 16)
   local status    = self:getbits(0x3C,  7,  1)

   checkz(status)

   return signature, token
end

--see 12.2 Return Status Summary
function cmdq:checkstatus()
   local status = self:getoutbits(0x00, 31, 24)
   local syndrome = self:getoutbits(0x04, 31, 0)
   if status == 0 then return end
   error(string.format('status: 0x%x, syndrome: %d', status, syndrome))
end

function cmdq:enable_hca()
   self:setinbits(0x00, 31, 16, ENABLE_HCA)
   self:post(0x0C, 0x08)
end

function cmdq:disable_hca()
   self:setinbits(0x00, 31, 16, DISABLE_HCA)
   self:post(0x0C, 0x08)
end

function cmdq:query_issi()
   self:setinbits(0x00, 31, 16, QUERY_ISSI)
   self:post(0x0C, 0x6C)
   self:checkstatus()
   local cur_issi = self:getoutbits(0x08, 15, 0)
   local t = {}
   for i=0,80-1 do
      t[i] = self:getbit(0x20, i) == 1 or nil
   end
   return {
      cur_issi = cur_issi,
      sup_issi = t,
   }
end

function cmdq:set_issi(issi)
   self:setinbits(0x00, 31, 16, SET_ISSI)
   self:setinbits(0x08, 15, 0, issi)
   self:post(0x0C, 0x0C)
   self:checkstatus()
end

function cmdq:dump_issi(issi)
   print('  cur_issi              ', issi.cur_issi)
   print('  sup_issi              ')
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
   self:setinbits(0x00, 31, 16, QUERY_PAGES)
   self:setinbits(0x04, 15, 0, codes[which])
   self:post(0x0C, 0x0C)
   self:checkstatus()
   return self:getoutbits(0x0C, 31, 0)
end

function cmdq:alloc_pages(addr, num_pages)
   self:setinbits(0x00, 31, 16, MANAGE_PAGES)
   self:setinbits(0x04, 15, 0, 1) --alloc
   self:setinbits(0x0C, 31, 0, num_pages)
   local addr = cast('char*', addr)
   for i=0, num_pages-1 do
      self:setinbits(0x10 + i*8, 31,  0, ptrbits(addr + 4096*i, 63, 32))
      self:setinbits(0x14 + i*8, 31, 12, ptrbits(addr + 4096*i, 31, 12))
   end
   self:post(0x10 + num_pages*8, 0x0C)
   self:checkstatus()
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
   self:setinbits(0x00, 31, 16, QUERY_HCA_CAP)
   self:setinbits(0x04,
      15,  1, assert(which_codes[which]),
       0,  0, assert(what_codes[what]))
   self:post(0x0C, 0x100C - 3000)
   self:checkstatus()
   local caps = {}
   if which_caps == 'general' then
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
   self:checkstatus()
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

   pci.unbind_device_from_linux(pciaddress)
   pci.set_bus_master(pciaddress, true)
   local base, fd = pci.map_pci_memory(pciaddress, 0)

   local init_seg = init_seg:init(base)

   --allocate and set the command queue which also initializes the nic
   local cmdq = cmdq:new(init_seg)

   --8.2 HCA Driver Start-up

   init_seg:cmdq_phy_addr(cmdq.phy)

   --wait until the nic is ready
   while not init_seg:ready() do
      C.usleep(1000)
   end

   init_seg:dump()

   cmdq:enable_hca()

   local issi = cmdq:query_issi()
   cmdq:dump_issi(issi)

   cmdq:set_issi(0)

   local boot_pages = cmdq:query_pages'boot'
   print("query_pages'boot'       ", boot_pages)
   assert(boot_pages > 0)

   local bp_ptr, bp_phy = memory.dma_alloc(4096 * boot_pages)
   assert(band(bp_phy, 0xfff) == 0) --the phy address must be 4K-aligned
   cmdq:alloc_pages(bp_phy, boot_pages)

   local t = cmdq:query_hca_cap('cur', 'general')
   print'query_hca_cap:'
   for k,v in pairs(t) do
      print('', k, v)
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
      if not base then return end
      if cmdq then
         cmdq:disable_hca()
      end
      pci.set_bus_master(pciaddress, false)
      pci.close_pci_resource(fd, base)
      base, fd = nil
   end

   return self
end

function selftest()
   io.stdout:setvbuf'no'

	local ptr, phy = alloc_pages(1)
	ptr[4] = bswap(1234)
	assert(getint(ptr, 16) == 1234)
	setint(ptr, 16, 4321)
	assert(bswap(ptr[4]) == 4321)
	assert(getint(ptr, 16) == 4321)
	assert(getbits(0xdeadbeef, 31, 16) == 0xdead)
	assert(getbits(0xdeadbeef, 15,  0) == 0xbeef)
	assert(ptrbits(ffi.cast('void*', 0xdeadbeef), 15, 0) == 0xbeef)
	assert(setbits(0, 0, 1) == 1)
	assert(setbits(1, 1, 1) == 2)
	assert(setbits(1, 0, 3) == 3)
	local x = setbits(31, 16, 0xdead, 15, 0, 0xbeef)
	print(bit.tohex(x), type(x))
	--assert(x == 0xdeadbeef)
	ptr[4] = bswap(2)
	assert(getbit(ptr, 4 * 4 * 8 + 0) == 0)
	assert(getbit(ptr, 4 * 4 * 8 + 1) == 1)

   local pcidev1 = lib.getenv("SNABB_PCI_CONNECTX40") or lib.getenv("SNABB_PCI0")
   local pcidev2 = lib.getenv("SNABB_PCI_CONNECTX41") or lib.getenv("SNABB_PCI1")
   if not pcidev1
      or pci.device_info(pcidev1).driver ~= 'apps.mellanox.connectx4'
      or not pcidev2
      or pci.device_info(pcidev2).driver ~= 'apps.mellanox.connectx4'
   then
      print("SNABB_PCI_CONNECTX4[0|1]/SNABB_PCI[0|1] not set or not suitable.")
      os.exit(engine.test_skipped_code)
   end

   local device_info_1 = pci.device_info(pcidev1)
   local device_info_2 = pci.device_info(pcidev2)

   local app1 = ConnectX4:new{pciaddress = pcidev1}
   local app2 = ConnectX4:new{pciaddress = pcidev2}

   engine.main({duration = 1, report={showlinks=true, showapps=false}})

   app1:stop()
   app2:stop()
end
