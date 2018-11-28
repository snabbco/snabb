module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local common = require("program.l2vpn.tunnels.common").tunnel
local gre = require("lib.protocol.gre")

tunnel = setmetatable({}, { __index = common })

function tunnel:new (config)
   local o = { vcs = {} }
   for vc_id, _ in pairs(config.vcs) do
      local header = gre:new({ protocol = 0x6558,
                               checksum = false,
                               key = vc_id })
      local vc = {
         header_in = header,
         header_out = header,
         link_name = "vc_"..vc_id
      }
      vc.header_in_ptr = ffi.cast("uint8_t *", header:header_ptr())
      vc.header_out_ptr = ffi.cast("uint8_t *", header:header_ptr())
      table.insert(o.vcs, vc)
   end
   -- The base GRE header does not include the key field
   o.header_size = gre:new({ key = 0}):sizeof()
   o.logger = lib.logger_new({ module = "GRE" })
   o.header_scratch = gre:new()
   o.handle_unknown_header_fn = function(self, p)
      if self.logger and self.logger:can_log() then
         local gre = self.header_scratch:new_from_mem(p.data, p.length)
         self.logger:log(("GRE unknown key: 0x%04x"):format(gre:key()))
      end
   end

   return setmetatable(o, { __index = tunnel })
end

function selftest ()
   local app_graph = config.new()
   local Source = require("apps.basic.basic_apps").Source
   local Sink = require("apps.basic.basic_apps").Sink
   local Join = require("apps.basic.basic_apps").Join

   local SourceGRE = {}
   function SourceGRE:new (key)
      local dgram = require("lib.protocol.datagram"):new()
      dgram:push(gre:new({ protocol = 0x6558,
                           checksum = false,
                           key = key }))
      return setmetatable({ dgram = dgram }, { __index = SourceGRE })
   end
   function SourceGRE:pull ()
      for _ = 1, engine.pull_npackets do
         link.transmit(self.output.output, packet.clone(self.dgram:packet()))
      end
   end

   local vcs = {}
   local nvcs = 4
   for vc_id = 1, nvcs do
      vcs[tostring(vc_id)] = {}

      config.app(app_graph, vc_id.."_south", SourceGRE, vc_id)
      config.app(app_graph, vc_id.."_north", Source)
      config.app(app_graph, vc_id.."_sink", Sink)

      config.link(app_graph, vc_id.."_south.output -> join."..vc_id)
      config.link(app_graph, "gre.vc_"..vc_id.." -> "..vc_id.."_sink.input")
      config.link(app_graph, vc_id.."_north.output -> gre.vc_"..vc_id)
   end
   config.app(app_graph, "noise", SourceGRE, math.random(2^32-1))
   config.link(app_graph, "noise.output -> join.noise")

   config.app(app_graph, "join", Join)
   config.app(app_graph, "gre", tunnel, { vcs = vcs })
   config.app(app_graph, "sink", Sink)

   config.link(app_graph, "join.output -> gre.south")
   config.link(app_graph, "gre.south -> sink.input")

   engine.configure(app_graph)
   engine.main({ duration = 1 })

   local counter = require("core.counter")
   local function packets (app, link, dir)
      local at = engine.app_table[app]
      return tonumber(counter.read(at[dir][link].stats.rxpackets))
   end

   for vc_id = 1, nvcs do
      assert(packets(vc_id.."_south", "output", "output") ==
                packets("gre", "vc_"..vc_id, "output"))
   end
end
