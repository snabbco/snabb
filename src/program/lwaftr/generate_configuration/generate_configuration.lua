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

local function softwire_entry(v4addr, psid, b4, br_address, port_set)
   if tonumber(v4addr) then v4addr = to_ipv4_string(v4addr) end
   local softwire = "  softwire { ipv4 %s; psid %d; b4-ipv6 %s; br-address %s;"
   softwire = softwire .. " port-set { psid-length %d; }}"
   return softwire:format(v4addr, psid, b4, br_address, port_set.psid_len)
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

local function softwire_iter (params)
   local v4addr = to_ipv4_u32(params.from_ipv4)
   local b4 = ipv6:pton(params.from_b4)
   local br_address = ipv6:pton(params.br_address)
   local n = 2^params.port_set.psid_len
   local psid = 1
   local nip = params.num_ips
   return function ()
      if not (nip > 0) then
         return
      end
      local softwire = {
         v4addr = to_ipv4_string(v4addr),
         psid = 0,
         b4 = ipv6:ntop(b4),
         br_address = ipv6:ntop(br_address),
         port_set = params.port_set
      }
      if params.port_set.psid_len == 0 then
         b4 = inc_ipv6(b4)
         v4addr = inc_ipv4(v4addr)
         nip = nip - 1
         return softwire
      else
         softwire.psid = psid
         b4 = inc_ipv6(b4)
         if psid < n then
            psid = psid + 1
         else
            psid = 1
            v4addr = inc_ipv4(v4addr)
            nip = nip - 1
         end
         return softwire
      end
   end
end

local function softwires(w, params)
   for s in softwire_iter(params) do
      w:ln(softwire_entry(s.v4addr, s.psid, s.b4, s.br_address, s.port_set))
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

local pcap_v4_file, pcap_v6_file
local packet_size, num_packets = 300, 1000

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
   handlers["6"] = function (arg)
      pcap_v6_file = arg
   end
   handlers["4"] = function (arg)
      pcap_v4_file = arg
   end
   function handlers.s (arg)
      packet_size = assert(tonumber(arg))
   end
   function handlers.n (arg)
      num_packets = assert(tonumber(arg))
   end
   function handlers.h() show_usage(0) end
   local long_opts = {
      help="h" , output="o",
      ['pcap-v6']="6",  ['pcap-v4']="4",
      ['packet-size']="s", ["npackets"]="n"
   }
   args = lib.dogetopt(args, handlers, "ho:6:4:s:n:", long_opts)
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


local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local udp = require("lib.protocol.udp")
local datagram = require("lib.protocol.datagram")
local pcap = require("lib.pcap.pcap")

local function psid_port (psid, port_set)
   local psid_mask = bit.lshift(1, port_set.psid_len) - 1
   return bit.lshift(bit.band(psid, psid_mask), port_set.shift or 0)
end

local function v4_packet (s, params)
   local dgram = datagram:new()
   local overhead = ethernet:sizeof()+ipv4:sizeof()+udp:sizeof()
   local len = math.max(4, params.packet_size-overhead)
   local payload = dgram:payload(("0"):rep(len), len)
   local udp = udp:new{
      src_port=12345,
      dst_port=psid_port(s.psid, s.port_set)
   }
   udp:length(len+udp:sizeof())
   local ip4 = ipv4:new{
      src=ipv4:pton("1.2.3.4"),
      dst=ipv4:pton(s.v4addr),
      ttl=15,
      protocol=17
   }
   ip4:total_length(udp:length()+ip4:sizeof())
   ip4:checksum()
   udp:checksum(payload, len, ip4)
   local eth = ethernet:new{
      src=ethernet:pton("68:68:68:68:68:68"),
      dst=ethernet:pton("12:12:12:12:12:12"),
      type=0x0800
   }
   dgram:push(udp)
   dgram:push(ip4)
   dgram:push(eth)
   return dgram:packet()
end

local function v6_packet (s, params)
   local dgram = datagram:new()
   local overhead = ethernet:sizeof()+ipv6:sizeof()+ipv4:sizeof()+udp:sizeof()
   local len = math.max(4, params.packet_size-overhead)
   local payload = dgram:payload(("0"):rep(len), len)
   local udp = udp:new{
      src_port=psid_port(s.psid, s.port_set),
      dst_port=12345
   }
   udp:length(len+udp:sizeof())
   local ip4 = ipv4:new{
      src=ipv4:pton(s.v4addr),
      dst=ipv4:pton("1.2.3.4"),
      ttl=15,
      protocol=17
   }
   ip4:total_length(udp:length()+ip4:sizeof())
   ip4:checksum()
   udp:checksum(payload, len, ip4)
   local ip6 = ipv6:new{
      src=ipv6:pton(s.b4),
      dst=ipv6:pton(s.br_address),
      next_header = 4,
      hop_limit = 255,
      traffic_class = 1
   }
   ip6:payload_length(ip4:total_length())
   local eth = ethernet:new{
      src=ethernet:pton("44:44:44:44:44:44"),
      dst=ethernet:pton("22:22:22:22:22:22"),
      type=0x86dd
   }
   dgram:push(udp)
   dgram:push(ip4)
   dgram:push(ip6)
   dgram:push(eth)
   return dgram:packet()
end

local function random_sample (array, n)
   local sample = {}
   for _=1,n do
      table.insert(sample, table.remove(array, math.random(#array)))
   end
   return sample
end

local function pcap_packets (params, template)
   local packets = {}
   for s in softwire_iter(params) do
      table.insert(packets, template(s, params))
   end
   return random_sample(packets, params.num_packets)
end

local function pcap_file (filename, params, template)
   local f = assert(io.open(filename, "w"))
   pcap.write_file_header(f)
   for _, p in ipairs(pcap_packets(params, template)) do
      pcap.write_record(f, p.data, p.length)
   end
   assert(f:close())
end

function run(args)
   local from_ipv4, num_ips, br_address, from_b4, psid_len, shift = parse_args(args)
   num_ips = assert(tonumber(num_ips))
   psid_len = assert(tonumber(psid_len))
   if not shift then
      shift = 16 - psid_len
   else
      shift = assert(tonumber(shift))
   end
   assert(psid_len + shift <= 16)

   local params = {
      from_ipv4 = from_ipv4,
      num_ips = num_ips,
      from_b4 = from_b4,
      br_address = br_address,
      port_set = {
         psid_len = psid_len,
         shift = shift
      },
      packet_size = packet_size,
      num_packets = num_packets
   }

   w:ln("softwire-config {") w:indent()
   w:ln("binding-table {") w:indent()
   softwires(w, params)
   w:unindent() w:ln("}")
   external_interface(w)
   internal_interface(w)
   instance(w)
   w:unindent() w:ln("}")

   if pcap_v4_file then
      pcap_file(pcap_v4_file, params, v4_packet)
   end

   if pcap_v6_file then
      pcap_file(pcap_v6_file, params, v6_packet)
   end

   main.exit(0)
end
