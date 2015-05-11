
inputi, outputi = {}, {}

function relink()
   inputi, outputi = {}, {}
   for _, l in pairs(output) do
      table.insert(outputi, l)
   end
   for _, l in pairs(input) do
      table.insert(inputi, l)
   end
end
