module(..., package.seeall)

local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

function pp(t) for k,v in pairs(t) do print(k,v) end end

function print_ethernet (addr)
   print(ethernet:ntop(addr))
end

function print_ipv6 (addr)
   print(ipv6:ntop(addr))
end

local function gen_hex_bytes(data, len)
   local fbytes = {}
   for i=0,len - 1 do
      table.insert(fbytes, string.format("0x%x", data[i]))
   end
   return fbytes
end

function print_hex(data, len)
   print(table.concat(gen_hex_bytes(data, len), " "))
end

-- Formats packet in 'od' format:
--
--    000000 00 0e b6 00 00 02 00 0e b6 00 00 01 08 00 45 00
--    000010 00 28 00 00 00 00 ff 01 37 d1 c0 00 02 01 c0 00
--    000020 02 02 08 00 a6 2f 00 01 00 01 48 65 6c 6c 6f 20
--    000030 57 6f 72 6c 64 21
--
-- A packet text dump in 'od' format can be easily converted into a pcap file:
--
--    $ text2pcap pkt.txt pkt.pcap
---
local function od_dump(pkt)
   local function column_index(i)
      return ("%.6x"):format(i)
   end
   local function column_value(val)
      return ("%.2x"):format(val)
   end
   local ret = {}
   for i=0, pkt.length-1 do
      if i == 0 then
         table.insert(ret, column_index(i))
      elseif i % 16 == 0 then
         table.insert(ret, "\n"..column_index(i))
      end
      table.insert(ret, column_value(pkt.data[i]))
   end
   return table.concat(ret, " ")
end

function print_pkt(pkt)
   print(("Len: %i, data:\n%s"):format(pkt.length, od_dump(pkt)))
end

function format_ipv4(uint32)
   return string.format("%i.%i.%i.%i",
      rshift(uint32, 24),
      rshift(band(uint32, 0xff0000), 16),
      rshift(band(uint32, 0xff00), 8),
      band(uint32, 0xff))
end

function selftest ()
   assert(format_ipv4(0xfffefdfc) == "255.254.253.252", "Bad conversion in format_ipv4")
end
