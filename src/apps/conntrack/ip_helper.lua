module(...,package.seeall)

local function ip_number_to_table(ip)
   local a = bit.band(bit.rshift(ip, 24), 0xFF)
   local b = bit.band(bit.rshift(ip, 16), 0xFF)
   local c = bit.band(bit.rshift(ip, 8), 0xFF)
   local d = bit.band(ip, 0xFF)
   return { a, b, c, d }
end

local function ip_string_to_table(ip)
   local result = {}
   for part in ip:gmatch("([^%.]+)%.?") do
      table.insert(result, tonumber(part))
   end
   return result
end

function as_ip_table(ip)
   assert(ip, "Argument cannot be nil")
   if type(ip) == "table" then return ip end
   if type(ip) == "number" then
      return ip_number_to_table(ip)
   end
   if type(ip) == "string" then
      return ip_string_to_table(ip)
   end
   error("Nil argument in 'as_ip_table'")
end

local function ip_table_to_string(ip)
   return ("%d.%d.%d.%d"):format(ip[1], ip[2], ip[3], ip[4])
end

local function ip_number_to_string(ip)
   return ip_table_to_string(ip_number_to_table(ip))
end

function as_ip_string(ip)
   assert(ip, "Argument cannot be nil")
   if type(ip) == "string" then return ip end
   if type(ip) == "number" then
      return ip_number_to_string(ip)
   end
   if type(ip) == "table" then
      return ip_table_to_string(ip)
   end
   error("Nil argument in 'as_ip_string'")
end

local function ip_table_to_number(ip)
   return ip[1] * 2^24 + ip[2] * 2^16 + ip[3] * 2^8 + ip[4]
end

local function ip_string_to_number(ip)
   return ip_table_to_number(ip_string_to_table(ip))
end

function as_ip_number(ip)
   assert(ip, "Argument cannot be nil")
   if type(ip) == "number" then return ip end
   if type(ip) == "string" then
      return ip_string_to_number(ip)
   end
   if type(ip) == "table" then
      return ip_table_to_number(ip)
   end
   error("Nil argument in 'as_ip_number'")
end

local function network_address(ip, mask)
   return as_ip_string(bit.band(
      as_ip_number(ip), as_ip_number(mask)))
end

function same_network(h1, h2, mask)
   local function equals(t1, t2)
      for i=1,#t1 do
         if t1[i] ~= t2[i] then return false end
      end
      return true
   end
   local n1 = as_ip_table(network_address(h1, mask))
   local n2 = as_ip_table(network_address(h2, mask))
   return equals(n1, n2)
end

function selftest()
   local function equals(t1, t2)
      if type(t1) ~= "table" and type(t2) ~= "table" then return false end
      if #t1 ~= #t2 then return false end
      for i=1,#t1 do
         if t1[i] ~= t2[i] then return false end
      end
      return true
   end

   local addr = "192.168.1.1"

   local ip = { 
      str = as_ip_string(addr),
      table = as_ip_table(addr),
      number = as_ip_number(addr),
   }

   local n1 = as_ip_number(ip.str)
   local n2 = as_ip_number(ip.table)
   assert(as_ip_number(ip.number) == ip.number and 
   n1 == n2, "As ip number failed")

   local n1 = as_ip_table(ip.str)
   local n2 = as_ip_table(ip.number)
   assert(equals(as_ip_table(ip.table), ip.table) and
   equals(n1, n2), "As ip table failed")

   local n1 = as_ip_string(ip.str)
   local n2 = as_ip_string(ip.number)
   assert(as_ip_string(ip.str) == ip.str and
   n1 == n2, "As ip string failed")

   local h1, h2, mask = "192.168.1.120", "192.168.1.1", "255.255.255.0"
   assert(same_network(h1, h2, mask), ("%s and %s are in the same network"))

   local h1, h2, mask = "118.143.88.102", "192.168.1.1", "255.255.255.0"
   assert(not same_network(h1, h2, mask), ("%s and %s are NOT in the same network"))

end

-- selftest()
