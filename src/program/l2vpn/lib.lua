module(...,package.seeall)

function eval (expr, msg)
   local result, err = loadstring("return ("..expr..")")
   assert(result, "Invalid Lua expression"..msg..": "
             ..expr..": "..(err or ''))
   return result()
end

function nil_or_empty_p (t)
   if not t then return true end
   assert(type(t) == "table", type(t))
   for _, _ in pairs(t) do
      return(false)
   end
   return(true)
end

function merge (a, b)
   for k, v in pairs(b) do
      a[k] = v
   end
end

function tlen (t)
   local length = 0
   for _, _ in pairs(t) do
      length = length + 1
   end
   return length
end

function singleton (t)
   assert(tlen(t) == 1)
   local iter, state = pairs(t)
   return iter(state)
end
