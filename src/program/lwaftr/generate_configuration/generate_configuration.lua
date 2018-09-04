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

local function inc_ipv4(uint32)
   return uint32 + 1
end

local function softwire_entry(v4addr, psid_len, b4, br_address, port_set)
   if tonumber(v4addr) then v4addr = to_ipv4_string(v4addr) end
   local softwire = "  softwire { ipv4 %s; psid %d; b4-ipv6 %s; br-address %s;"
   softwire = softwire .. " port-set { psid-length %d; }}"
   return softwire:format(v4addr, psid_len, b4, br_address, port_set.psid_len)
end

local function inc_ipv6(ipv6)
   for i = 15, 0, -1 do
      if ipv6[i] == 255 then
         ipv6[i] = 0
      else
         ipv6[i] = ipv6[i] + 1
         break
      end
   end
   return ipv6
end

local function softwires(w, params)
   local v4addr = to_ipv4_u32(params.from_ipv4)
   local b4 = ipv6:pton(params.from_b4)
   local br_address = ipv6:pton(params.br_address)
   local n = 2^params.psid_len
   for _ = 1, params.num_ips do
      if params.psid_len == 0 then
         w:ln(softwire_entry(v4addr, 0, ipv6:ntop(b4),
              ipv6:ntop(br_address), params.port_set))
         b4 = inc_ipv6(b4)
      else
         for psid = 1, n-1 do
            w:ln(softwire_entry(v4addr, psid, ipv6:ntop(b4),
                 ipv6:ntop(br_address), params.port_set))
            b4 = inc_ipv6(b4)
         end
      end
      v4addr = inc_ipv4(v4addr)
   end
end

local w = {tabs=0}
function w:ln(...)
   io.write(...) io.write("\n")
end
function w:close()

end
function w:indent()
   self.tabs = self.tabs + 1
end
function w:unindent()
   assert(self.tabs > 0)
   self.tabs = self.tabs - 1
end

function show_usage(code)
   print(require("program.lwaftr.generate_configuration.README_inc"))
   main.exit(code)
end

local function parse_args(args)
   local handlers = {}
   function handlers.o(arg)
      local fd = assert(io.open(arg, "w"),
         ("Couldn't find %s"):format(arg))
      function w:ln(...)
         fd:write(string.rep("   ", self.tabs))
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

local function lint (text)
   local t = {}
   local tabs = 0
   function put (line)
      table.insert(t, string.rep("   ", tabs)..line)
   end
   function flush ()
      return table.concat(t, "\n")
   end
   for line in text:gmatch("([^\n]+)") do
      line = line:gsub("^%s+", "")
      if line:sub(#line, #line) == '{' then
         put(line)
         tabs = tabs + 1
      elseif line:sub(#line, #line) == '}' then
         tabs = tabs - 1
         put(line)
      else
         put(line)
      end
   end
   return flush()
end

local function external_interface (w)
   local text = lint[[
      external-interface {
         allow-incoming-icmp false;
         error-rate-limiting {
            packets 600000;
         }
         reassembly {
            max-fragments-per-packet 40;
         }
      }
   ]]
   for line in text:gmatch("([^\n]+)") do
      w:ln(line)
   end
end
local function internal_interface (w)
   local text = lint[[
      internal-interface {
         allow-incoming-icmp false;
         error-rate-limiting {
            packets 600000;
         }
         reassembly {
            max-fragments-per-packet 40;
         }
      }
   ]]
   for line in text:gmatch("([^\n]+)") do
      w:ln(line)
   end
end
local function instance (w)
   local text = lint[[
      instance {
          device test;
          queue {
              id 0;
              external-interface {
                  ip 10.0.1.1;
                  mac 02:aa:aa:aa:aa:aa;
                  next-hop {
                      mac 02:99:99:99:99:99;
                  }
              }
              internal-interface {
                  ip fc00::100;
                  mac 02:aa:aa:aa:aa:aa;
                  next-hop {
                      mac 02:99:99:99:99:99;
                  }
              }
          }
      }
   ]]
   for line in text:gmatch("([^\n]+)") do
      w:ln(line)
   end
end

function run(args)
   local from_ipv4, num_ips, br_address, from_b4, psid_len, shift = parse_args(args)
   psid_len = assert(tonumber(psid_len))
   if not shift then
      shift = 16 - psid_len
   else
      shift = assert(tonumber(shift))
   end
   assert(psid_len + shift <= 16)

   w:ln("softwire-config {") w:indent()
   w:ln("binding-table {") w:indent()
   softwires(w, {
      from_ipv4 = from_ipv4,
      num_ips = num_ips,
      from_b4 = from_b4,
      psid_len = psid_len,
      br_address = br_address,
      port_set = {
         psid_len = psid_len,
         shift = shift
      }
   })
   w:unindent() w:ln("}")
   external_interface(w)
   internal_interface(w)
   instance(w)
   w:unindent() w:ln("}")

   main.exit(0)
end
