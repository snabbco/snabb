module(..., package.seeall)

local lib  = require("core.lib")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local util = require("apps.wall.util")
local scan = require("apps.wall.scanner")

local long_opts = {
   help    = "h",
   verbose = "v",
}

local function printf(fmt, ...)
   io.write(fmt:format(...))
end

local function report_flow(scanner, flow)
   local lo_addr, hi_addr = "<unknown>", "<unknown>"
   local eth_type = flow.key:eth_type()
   if eth_type == scan.ETH_TYPE_IPv4 then
      lo_addr = ipv4:ntop(flow.key.lo_addr)
      hi_addr = ipv4:ntop(flow.key.hi_addr)
   elseif eth_type == scan.ETH_TYPE_IPv6 then
      lo_addr = ipv6:ntop(flow.key.lo_addr)
      hi_addr = ipv6:ntop(flow.key.hi_addr)
   end

   printf("%#010x %4dp %15s:%-5d - %15s:%-5d  %s:%s\n",
      flow.key:hash(), flow.packets,
      lo_addr, flow.key.lo_port,
      hi_addr, flow.key.hi_port,
      scanner:protocol_name(flow.protocol),
      scanner:protocol_name(flow.proto_master))
end

local Report = setmetatable({}, util.SouthAndNorth)
Report.__index = Report

function Report:new (scanner)
   return setmetatable({
      scanner = scanner,
      packets = 0,
   }, self)
end

function Report:on_northbound_packet (p)
   self.packets = self.packets + 1
   local flow = self.scanner:get_flow(p)
   if flow and not flow.reported then
      local proto = self.scanner:protocol_name(flow.protocol)
      if proto:lower() ~= "unknown" then
         report_flow(self.scanner, flow)
         flow.reported = true
      end
   end
end
Report.on_southbound_packet = Report.on_northbound_packet


local inputs = {}

function inputs.pcap (kind, path)
   return "output", { require("apps.pcap.pcap").PcapReader, path }
end

function inputs.raw (kind, device)
   return "output", { require("apps.socket.raw").RawSocket, device }
end

function inputs.tap (kind, device)
   return "output", { require("apps.tap.tap").Tap, device }
end

function inputs.intel10g (kind, device)
   local conf = { pciaddr = device }
   return "rx", { require("apps.intel.intel_app").Intel10G, conf }
end

function inputs.intel1g (kind, device)
   local conf = { pciaddr = device }
   return "rx", { require("apps.intel.intel1g").Intel1G, conf }
end


local function setup_input(c, input_spec)
   local kind, arg = input_spec_pattern:match(input_spec)
   if not kind then
      kind, arg = "pcap", input_spec
   end
   if not inputs[kind] then
      return nil, "No such input kind: " .. kind
   end
   return inputs[kind](kind, arg)
end


function run (args)
   local verbosity = 0
   local opt = {
      v = function (arg)
         verbosity = verbosity + 1
      end,
      h = function (arg)
         print(require("program.wall.spy.README_inc"))
         main.exit(0)
      end,
   }

   args = lib.dogetopt(args, opt, "hv", long_opts)
   if #args ~= 2 then
      print(require("program.wall.spy.README_inc"))
      main.exit(1)
   end

   if not inputs[args[1]] then
      io.stderr:write("No such input available: ", args[1], "\n")
      main.exit(1)
   end

   local source_link_name, app = inputs[args[1]](args[1], args[2])
   if not source_link_name then
      io.stderr:write(app, "\n")
      main.exit(1)
   end

   -- FIXME: When multiple scanners are available, allow selecting others.
   local s = require("apps.wall.scanner.ndpi"):new()

   local c = config.new()
   config.app(c, "source", unpack(app))
   config.app(c, "l7spy", require("apps.wall.l7spy").L7Spy, { scanner = s })
   config.link(c, "source." .. source_link_name .. " -> l7spy.south")

   if verbosity > 0 then
      config.app(c, "report", Report, s)
      config.link(c, "l7spy.north -> report.south")
   end

   engine.configure(c)
   engine.busywait = true
   engine.main {
      done = function ()
         return engine.app_table.source.done
      end
   }
end
