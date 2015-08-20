module(..., package.seeall)

function pp(t) for k,v in pairs(t) do print(k,v) end end

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
