module(..., package.seeall)

function cardinality(kw, path, statements, haystack)
   for s, c in pairs(statements) do
      if (c[1] >= 1 and (not haystack[s])) or
         (#statements[s] < c[1] and #statements[s] > c[2]) then
         if c[1] == c[2] then
            error(("Expected %d %s statement(s) in %s:%s"):format(
               c[1], s, kw, path))
         else
            local err = "Expected between %d and %d of %s statement(s) in %s:%s"
            error((err):format(c[1], c[2], s, kw, path))
         end
      end
   end
   return true
end
