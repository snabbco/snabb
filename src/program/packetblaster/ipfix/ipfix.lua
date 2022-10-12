-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local connectx   = require("apps.mellanox.connectx") 
local basic_apps = require("apps.basic.basic_apps")
local PcapReader = require("apps.pcap.pcap").PcapReader
local numa       = require("lib.numa")
local worker     = require("core.worker")
local lib        = require("core.lib")

local long_opts = {
   duration           = "D",
   nqueues            = "q",
   ["new-flows-freq"] = "f",
   help               = "h"
}

local function show_usage (code)
   print(require("program.packetblaster.replay.README_inc"))
   main.exit(code)
end

function run (args)
   local handlers = {}
   local opts = { nqueues = 1, duration = nil, flow_Hz = 150 }
   function handlers.D (arg)
      opts.duration = assert(tonumber(arg), "duration is not a number!")
   end
   function handlers.q (arg)
      opts.nqueues = assert(tonumber(arg), "nqueues is not a number!")
   end
   function handlers.f (arg)
      opts.flow_Hz = assert(tonumber(arg), "new-flows-freq is not a number!")
   end
   function handlers.h ()
      show_usage(0)
   end

   args = lib.dogetopt(args, handlers, "hD:q:f:", long_opts)
   if #args < 3 then show_usage(1) end
   local filename = table.remove(args, 1)
   local pci = table.remove(args, 1)
   local cpus = assert(numa.parse_cpuset(table.remove(args, 1)), "Invalid cpu set")
   print (string.format("filename=%s", filename))

   local queues = {}
   for cpu in pairs(cpus) do
      for q=1, opts.nqueues do
         table.insert(queues, {id=("%d_%d"):format(cpu, q)})
      end
   end
   assert(#queues > 0, "Need atleast one cpu.")

   local c = config.new()
   config.app(c, "ConnectX", connectx.ConnectX, {
      pciaddress = pci,
      queues = queues,
      sendq_size = 4096
   })
   engine.configure(c)

   for cpu in pairs(cpus) do
      worker.start(
         "loadgen"..cpu,
         ([[require("program.packetblaster.ipfix.ipfix").run_loadgen(
            %q, %q, %d, %d, %s, %d)]])
            :format(filename, pci, cpu, opts.nqueues, opts.duration, opts.flow_Hz)
      )
   end

   local function worker_alive ()
      for w, status in pairs(worker.status()) do
         if status.alive then
            return true
         end
      end
   end

   while worker_alive() do
      engine.main{duration=1, no_report=true}
      print("Transmissions (last 1 sec):")
      engine.report_apps()
   end
end

function run_loadgen (filename, pci, cpu, nqueues, duration, flow_Hz)
   local c = config.new()
   config.app(c, "pcap", PcapReader, filename)
   config.app(c, "repeater", basic_apps.Repeater)
   config.app(c, "flowgen", Flowgen, {Hz=flow_Hz})
   config.app(c, "source", basic_apps.Tee)
   config.link(c, "pcap.output -> repeater.input")
   config.link(c, "repeater.output -> flowgen.input")
   config.link(c, "flowgen.output -> source.input")
   for q=1, nqueues do
      config.app(c, "nic"..q, connectx.IO, {
         pciaddress = pci,
         queue = ("%d_%d"):format(cpu, q)
      })
      config.link(c, "source.output"..q.." -> nic"..q..".input")
   end
   engine.configure(c)
   engine.main{duration=duration}
end

local ethernet = require("lib.protocol.ethernet")
local dot1q = require("lib.protocol.dot1q")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local ffi  = require("ffi")

Flowgen = {
   config = {
      Hz = {default=100000}
   }
}

function Flowgen:new (config)
   local self = {
      inc = 0ULL,
      inc_throttle = lib.throttle(1/config.Hz),
      dot1q = dot1q:new{},
      ipv4 = ipv4:new{},
      ipv6 = ipv6:new{}
   }
   return setmetatable(self, {__index=Flowgen})
end

function Flowgen:push ()
   if self.inc_throttle() then
      self.inc = (self.inc + 1)
   end
   local input, output = self.input.input, self.output.output
   while not link.empty(input) do
      local p = link.receive(input)
      if self:inc_l3_addresses(p) then
         link.transmit(output, p)
      else
         packet.free(p)
      end
   end
end

function Flowgen:inc_l3_addresses (p)
   local inc = self.inc
   local vlan = self.dot1q:new_from_mem(
      p.data+ethernet:sizeof(),
      p.length-ethernet:sizeof()
   )
   if not vlan then return false end
   if vlan:type() == 0x0800 then -- IPv4
      local ip = self.ipv4:new_from_mem(
         p.data+ethernet:sizeof()+dot1q:sizeof(),
         p.length-(ethernet:sizeof()+dot1q:sizeof())
      )
      if not ip then return false end
      self:inc_ip(ip:src(), inc)
      self:inc_ip(ip:dst(), inc)
      return true
   elseif vlan:type() == 0x86dd then -- IPv6
      local ip = self.ipv6:new_from_mem(
         p.data+ethernet:sizeof()+dot1q:sizeof(),
         p.length-(ethernet:sizeof()+dot1q:sizeof())
      )
      if not ip then return false end
      self:inc_ip(ip:src(), inc)
      self:inc_ip(ip:dst(), inc)
      return true
   else
      return false
   end
end

function Flowgen:inc_ip (addr, inc)
   local addr = ffi.cast("uint32_t*", addr)
   addr[0] = addr[0] + inc
end

