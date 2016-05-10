module(...,package.seeall)

local bit = require("bit")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local lib = require("core.lib")

local band, rshift = bit.band, bit.rshift

local function to_ipv4_string(uint32)
   return ("%i.%i.%i.%i"):format(
      rshift(uint32, 24),
      rshift(band(uint32, 0xff0000), 16),
      rshift(band(uint32, 0xff00), 8),
      band(uint32, 0xff))
end

local function to_ipv4_u32(ip)
   assert(type(ip) == "string")
   ip = ipv4:pton(ip)
   return ip[0] * 2^24 + ip[1] * 2^16 + ip[2] * 2^8 + ip[3]
end

local function psid_map_entry(ipv4, psid_len, shift)
   if tonumber(ipv4) then ipv4 = to_ipv4_string(ipv4) end
   return ("%s { psid_length=%d, shift=%d }"):format(ipv4, psid_len, shift) 
end

local function inc_ipv4(uint32)
   return uint32 + 1
end

local function psid_map_entries(params)
   local entries = {}
   local ipv4 = params.from_ipv4
   if type(ipv4) == "string" then ipv4 = to_ipv4_u32(ipv4) end
   assert(type(ipv4) == "number")
   for i=1,params.num_ips do
      table.insert(entries, psid_map_entry(ipv4, params.psid_len, params.shift))
      ipv4 = inc_ipv4(ipv4)
   end
   return entries
end

local function psid_map(w, params)
   w:ln("psid_map {")
   for _, entry in ipairs(psid_map_entries(params)) do
      w:ln("  "..entry)
   end
   w:ln("}")
end

local function br_addresses(w, br_address)
   w:ln("br_addresses {")
   w:ln("  "..br_address)
   w:ln("}")
end

local function softwire_entry(ipv4, psid_len, b4)
   if tonumber(ipv4) then ipv4 = to_ipv4_string(ipv4) end
   return ("{ ipv4=%s, psid=%d, b4=%s }"):format(ipv4, psid_len, b4)
end

local function inc_ipv6(ipv6)
   for i=15,0,-1 do
      if ipv6[i] == 255 then 
         ipv6[i] = 0
      else
         ipv6[i] = ipv6[i] + 1
         break
      end
   end
   return ipv6
end

local function softwire_entries(from_ipv4, num_ips, psid_len, from_b4)
   local entries = {}
   local ipv4 = to_ipv4_u32(from_ipv4)
   local b4 = ipv6:pton(from_b4)
   local n = 2^psid_len
   for i=1,num_ips do
      for psid=1,n-1 do
         table.insert(entries, softwire_entry(ipv4, psid, ipv6:ntop(b4)))
         b4 = inc_ipv6(b4)
      end
      ipv4 = inc_ipv4(ipv4)
   end
   return entries
end

local function softwires(w, params)
   w:ln("softwires {")
   local entries = softwire_entries(params.from_ipv4, params.num_ips,
      params.psid_len, params.from_b4)
   for _, entry in ipairs(entries) do
      w:ln("  "..entry)
   end
   w:ln("}")
end

local w = {}
function w:ln(...)
   io.write(...) io.write("\n")
end
function w:close()

end

function show_usage(code)
   print(require("program.lwaftr.generate_binding_table.README_inc"))
   main.exit(code)
end

function parse_args(args)
   local handlers = {}
   function handlers.o(arg)
      local fd = assert(io.open(arg, "w"), 
         ("Couldn't find %s"):format(arg))
      function w:ln(...)
         fd:write(...) fd:write("\n")
      end
      function w:close()
         fd:close()
      end
   end
   function handlers.h() show_usage(0) end
   args = lib.dogetopt(args, handlers, "ho:", { help="h" , output="o" })
   if #args < 1 or #args > 6 then show_usage(1) end
   return unpack(args)
end

function run(args)
   local from_ipv4, num_ips, br_address, from_b4, psid_len, shift = parse_args(args)
   psid_len = assert(tonumber(psid_len))
   if not shift then shift = 16 - psid_len end
   assert(psid_len + shift == 16)

   psid_map(w, {
      from_ipv4 = from_ipv4,
      num_ips = num_ips,
      psid_len = psid_len,
      shift = shift,
   })
   br_addresses(w, br_address)
   softwires(w, {
      from_ipv4 = from_ipv4,
      num_ips = num_ips,
      from_b4 = from_b4,
      psid_len = psid_len,
   })
   w:close()
   
   main.exit(0)
end
