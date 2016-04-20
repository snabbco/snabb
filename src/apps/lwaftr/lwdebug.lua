module(..., package.seeall)

local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

function pp(t) for k,v in pairs(t) do print(k,v) end end

function print_ethernet(addr)
   chunks = {}
   for i = 0,5 do
      table.insert(chunks, string.format("%x", addr[i]))
   end
   print(table.concat(chunks, ':'))
end

function print_ipv6(addr)
   chunks = {}
   for i = 0,7 do
      table.insert(chunks, string.format("%x%x", addr[2*i], addr[2*i+1]))
   end
   print(table.concat(chunks, ':'))
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

function print_pkt(pkt)
   local fbytes = gen_hex_bytes(pkt.data, pkt.length)
   print(string.format("Len: %i: ", pkt.length) .. table.concat(fbytes, " "))
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
