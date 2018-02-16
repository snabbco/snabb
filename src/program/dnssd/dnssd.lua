-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local DNS = require("lib.protocol.dns.dns").DNS
local MDNS = require("lib.protocol.dns.mdns").MDNS
local RawSocket = require("apps.socket.raw").RawSocket
local basic_apps = require("apps.basic.basic_apps")
local ffi = require("ffi")
local lib = require("core.lib")
local mDNSQuery = require("lib.protocol.dns.mdns_query").mDNSQuery
local pcap = require("apps.pcap.pcap")

local long_opts = {
   help = "h",
   pcap = "p",
   interface = "i",
}

local function usage(exit_code)
   print(require("program.dnssd.README_inc"))
   main.exit(exit_code)
end

function parse_args (args)
   local function fexists (filename)
      local fd = io.open(filename, "r")
      if fd then
         fd:close()
         return true
      end
      return false
   end
   local opts = {}
   local handlers = {}
   function handlers.h (arg)
      usage(0)
   end
   function handlers.p (arg)
      opts.pcap = arg
   end
   function handlers.i (arg)
      opts.interface = arg
   end
   args = lib.dogetopt(args, handlers, "hp:i:", long_opts)
   if not (opts.pcap or opts.interface) then
      local filename = args[1]
      if fexists(filename) then
         opts.pcap = filename
      else
         opts.interface = filename
      end
      table.remove(args, 1)
   end
   return opts, args
end

DNSSD = {}

function DNSSD:new (args)
   local o = {
      interval = 1, -- Delay between broadcast messages.
      threshold = 0,
   }
   if args then
      o.requester = mDNSQuery.new({
         src_eth = assert(args.src_eth),
         src_ipv4 = assert(args.src_ipv4),
      })
      o.query = args.query or "_services._dns-sd._udp.local"
   end
   return setmetatable(o, {__index = DNSSD})
end

-- Generate a new broadcast mDNS packet every interval seconds.
function DNSSD:pull ()
   local output = self.output.output
   if not output then return end

   local now = os.time()
   if now > self.threshold then
      self.threshold = now + self.interval
      local pkt = self.requester:build(self.query)
      link.transmit(output, pkt)
   end
end

function DNSSD:push ()
   local input = assert(self.input.input)

   while not link.empty(input) do
      local pkt = link.receive(input)
      if MDNS.is_mdns(pkt) then
         self:log(pkt)
      end
      packet.free(pkt)
   end
end

function DNSSD:log (pkt)
   if not MDNS.is_response(pkt) then return end
   local response = MDNS.parse_packet(pkt)
   local answer_rrs = response.answer_rrs
   if #answer_rrs > 0 then
      for _, rr in ipairs(answer_rrs) do
         print(rr:tostring())
      end
   end
   local additional_rrs = response.additional_rrs
   if #additional_rrs > 0 then
      for _, rr in ipairs(additional_rrs) do
         print(rr:tostring())
      end
   end
end

local function execute (cmd)
   local fd = assert(io.popen(cmd, 'r'))
   local ret = fd:read("*all")
   fd:close()
   return ret
end

local function chomp (str)
   return str:gsub("\n", "")
end

local function ethernet_address_of (iface)
   local cmd = ("ip li sh %s | grep 'link/ether' | awk '{print $2}'"):format(iface)
   local ret = chomp(execute(cmd))
   if #ret == 0 then
      print(("Unsupported interface: '%s' (missing MAC address)"):format(iface))
      os.exit()
   end
   return ret
end

local function ipv4_address_of (iface)
   local cmd = ("ip addr sh %s | grep 'inet ' | awk '{print $2}'"):format(iface)
   local output = chomp(execute(cmd))
   local pos = output:find("/")
   return pos and output:sub(0, pos-1) or output
end

function run(args)
   local opts, args = parse_args(args)

   local duration
   local c = config.new()
   if opts.pcap then
      print("Reading from file: "..opts.pcap)
      config.app(c, "dnssd", DNSSD)
      config.app(c, "pcap", pcap.PcapReader, opts.pcap)
      config.link(c, "pcap.output-> dnssd.input")
      duration = 3
   elseif opts.interface then
      local iface = opts.interface
      local query = args[1]
      local src_eth = ethernet_address_of(iface)
      print(("Capturing packets from interface '%s'"):format(iface))
      config.app(c, "dnssd", DNSSD, {
         src_eth = src_eth,
         src_ipv4 = ipv4_address_of(iface),
         query = query,
      })
      config.app(c, "iface", RawSocket, iface)
      config.link(c, "iface.tx -> dnssd.input")
      config.link(c, "dnssd.output -> iface.rx")
   else
      error("Unreachable")
   end
   engine.busy = false
   engine.configure(c)
   engine.main({duration = duration, report = {showapps = true, showlinks = true}})
end
