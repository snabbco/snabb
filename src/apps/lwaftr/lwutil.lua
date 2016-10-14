module(..., package.seeall)

local constants = require("apps.lwaftr.constants")

local S = require("syscall")
local bit = require("bit")
local ffi = require("ffi")
local lib = require("core.lib")

local band = bit.band
local cast = ffi.cast

local uint16_ptr_t = ffi.typeof("uint16_t*")
local uint32_ptr_t = ffi.typeof("uint32_t*")

local constants_ipv6_frag = constants.ipv6_frag
local ehs = constants.ethernet_header_size
local o_ipv4_flags = constants.o_ipv4_flags
local ntohs = lib.ntohs

function get_ihl_from_offset(pkt, offset)
   local ver_and_ihl = pkt.data[offset]
   return band(ver_and_ihl, 0xf) * 4
end

-- The rd16/wr16/rd32/wr32 functions are provided for convenience.
-- They do NO conversion of byte order; that is the caller's responsibility.
function rd16(offset)
   return cast(uint16_ptr_t, offset)[0]
end

function wr16(offset, val)
   cast(uint16_ptr_t, offset)[0] = val
end

function rd32(offset)
   return cast(uint32_ptr_t, offset)[0]
end

function wr32(offset, val)
   cast(uint32_ptr_t, offset)[0] = val
end

function keys(t)
   local result = {}
   for k,_ in pairs(t) do
      table.insert(result, k)
   end
   return result
end

local uint64_ptr_t = ffi.typeof('uint64_t*')
function ipv6_equals(a, b)
   local x, y = ffi.cast(uint64_ptr_t, a), ffi.cast(uint64_ptr_t, b)
   return x[0] == y[0] and x[1] == y[1]
end

-- Local bindings for constants that are used in the hot path of the
-- data plane.  Not having them here is a 1-2% performance penalty.
local o_ethernet_ethertype = constants.o_ethernet_ethertype
local n_ethertype_ipv4 = constants.n_ethertype_ipv4
local n_ethertype_ipv6 = constants.n_ethertype_ipv6

function is_ipv6(pkt)
   return rd16(pkt.data + o_ethernet_ethertype) == n_ethertype_ipv6
end

function is_ipv4(pkt)
   return rd16(pkt.data + o_ethernet_ethertype) == n_ethertype_ipv4
end

function is_ipv6_fragment(pkt)
   if not is_ipv6(pkt) then return false end
   return pkt.data[ehs + constants.o_ipv6_next_header] == constants_ipv6_frag
end

function is_ipv4_fragment(pkt)
   if not is_ipv4(pkt) then return false end
   -- Either the packet has the "more fragments" flag set,
   -- or the fragment offset is non-zero, or both.
   local flag_more_fragments_mask = 0x2000
   local non_zero_offset = 0x1FFF
   local flags_and_frag_offset = ntohs(rd16(pkt.data + ehs + o_ipv4_flags))
   return band(flags_and_frag_offset, flag_more_fragments_mask) ~= 0 or
      band(flags_and_frag_offset, non_zero_offset) ~= 0
end

function set_dst_ethernet(pkt, dst_eth)
   ffi.copy(pkt.data, dst_eth, 6)
end

function write_to_file(filename, content)
   local fd, err = io.open(filename, "wt+")
   if not fd then error(err) end
   fd:write(content)
   fd:close()
end

function fatal (msg)
   print(msg)
   main.exit(1)
end

function file_exists(path)
   local stat = S.stat(path)
   return stat and stat.isreg
end

function dir_exists(path)
   local stat = S.stat(path)
   return stat and stat.isdir
end

function nic_exists(pci_addr)
   local devices="/sys/bus/pci/devices"
   return dir_exists(("%s/%s"):format(devices, pci_addr)) or
      dir_exists(("%s/0000:%s"):format(devices, pci_addr))
end
