module(..., package.seeall)

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

function print_pkt(pkt)
   local fbytes = {}
   for i=0,pkt.length - 1 do
      table.insert(fbytes, string.format("0x%x", pkt.data[i]))
   end
   print(string.format("Len: %i: ", pkt.length) .. table.concat(fbytes, " "))
end

function format_ipv4(uint32)
   return string.format("%i.%i.%i.%i",
      bit.rshift(bit.band(uint32, 0xff000000), 24),
      bit.rshift(bit.band(uint32, 0xff0000), 16),
      bit.rshift(bit.band(uint32, 0xff00), 8),
      bit.band(uint32, 0xff))
end

function csum_carry_and_not(checksum)
   while checksum > 0xffff do -- process the carry nibbles
      local carry = bit.rshift(checksum, 16)
      checksum = bit.band(checksum, 0xffff) + carry
   end
   return bit.band(bit.bnot(checksum), 0xffff)
end

-- The checksum bytes must be set to 0 before calling this.
function ipv4_checksum(pkt, start_offset, bytes_to_checksum)
   print(start_offset, bytes_to_checksum)
   local checksum = 0
   for i = start_offset, start_offset + bytes_to_checksum + 2, 2 do
      checksum = checksum + pkt.data[i] * 0x100 + pkt.data[i+1]
   end
   return csum_carry_and_not(checksum)
end
