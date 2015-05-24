
function push()
   for _, i in ipairs(input) do
      for _ = 1, link.nreadable(i) do
         local p = link.receive(i)
         packet.free(p)
      end
   end
end
