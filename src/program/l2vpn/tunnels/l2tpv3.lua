module(..., package.seeall)
local ffi = require("ffi")
local base = require("program.l2vpn.tunnels.base").tunnel
local lib = require("program.l2vpn.lib")
local l2tpv3 = require("lib.protocol.keyed_ipv6_tunnel")

local eval = lib.eval

tunnel = setmetatable({}, { __index = base })

local params = {
   -- The spec for L2TPv3 over IPv6 recommends to set the session ID
   -- to 0xffffffff for the "static 1:1 mapping" scenario.
   local_session = { default = 0xffffffff },
   remote_session = { default = 0xffffffff },
   local_cookie = { required = true },
   remote_cookie = { required = true },
}

function tunnel:new (config)
   local function create_headers (_, config)
      return l2tpv3:new({ session_id = config.local_session,
                          cookie = l2tpv3:new_cookie(config.local_cookie) }),
      l2tpv3:new({ session_id = config.remote_session,
                   cookie = l2tpv3:new_cookie(config.remote_cookie) })
   end
   local function unknown_header (self, p, ancillary_data)
      if self.logger and self.logger:can_log() then
         local l2tpv3 = self.header_scratch:new_from_mem(p.data, p.length)
         self.logger:log(("%s -> %s : unknown session/cookie: 0x%08x/%s"):format(
               ancillary_data.remote_addr, ancillary_data.local_addr,
               l2tpv3:session_id(), l2tpv3:cookie()))
      end
   end

   return self:_new(config, "L2TPv3", l2tpv3, l2tpv3:sizeof(), params, create_headers,
                    unknown_header)
end

function tunnel:info ()
   return {
      params = {
         local_cookie = { required = true },
         remote_cookie = { required = true }
      },
      proto = 115,
      mk_vc_config_fn = function (vc_id, cc_vc_id, tunnel_config)
         local function maybe_eval_cookie(name)
            local s = tunnel_config[name]
            if s then
               tunnel_config[name] = eval("'"..s.."'",'')
            end
         end
         for _, cookie in ipairs({ 'local_cookie', 'remote_cookie' }) do
            maybe_eval_cookie(cookie)
         end
         return {
            [vc_id] = tunnel_config,
            [cc_vc_id] = {
               local_session = 0xFFFFFFFE,
               remote_session = 0xFFFFFFFE,
               local_cookie = tunnel_config.local_cookie,
               remote_cookie = tunnel_config.remote_cookie,
            }
         }
      end,
      afs = {
         ipv6 = true
      }
   }
end

function selftest ()
   local app_graph = config.new()
   local Source = require("apps.basic.basic_apps").Source
   local Sink = require("apps.basic.basic_apps").Sink
   local Join = require("apps.basic.basic_apps").Join

   local SourceL2TPv3 = {}
   function SourceL2TPv3:new (conf)
      local dgram = require("lib.protocol.datagram"):new()
      dgram:push(l2tpv3:new({ session_id = conf.session,
                              cookie = l2tpv3:new_cookie(conf.cookie) }))
      return setmetatable({ dgram = dgram }, { __index = SourceL2TPv3 })
   end
   function SourceL2TPv3:pull ()
      for _ = 1, engine.pull_npackets do
         link.transmit(self.output.output, packet.clone(self.dgram:packet()))
      end
   end

   local function random_cookie ()
      local cookie = ffi.new("uint64_t [1]")
      cookie[0] = math.random(2^64-1)
      return ffi.string(cookie, 8)
   end

   local vcs, vcs_rev = {}, {}
   local nvcs = 4
   for vc_id = 1, nvcs do
      local vc = {
         local_session = math.random(2^32-1),
         local_cookie = random_cookie(),
         remote_session = math.random(2^32-1),
         remote_cookie = random_cookie(),
      }
      local vc_rev = {
         local_session = vc.remote_session,
         remote_session = vc.local_session,
         local_cookie = vc.remote_cookie,
         remote_cookie = vc.local_cookie,
      }
      vcs[tostring(vc_id)] = vc
      vcs_rev[tostring(vc_id)] = vc_rev

      config.app(app_graph, vc_id.."_remote" , SourceL2TPv3,
                 { session = vc.local_session,
                   cookie = vc.local_cookie })
      config.app(app_graph, vc_id.."_local" , Source)
      config.app(app_graph, vc_id.."_sink_remote", Sink)
      config.app(app_graph, vc_id.."_sink_local", Sink)

      config.link(app_graph, vc_id.."_remote.output -> join."..vc_id)
      config.link(app_graph, "l2tpv3.vc_"..vc_id.." -> "..vc_id.."_sink_local.input")
      config.link(app_graph, vc_id.."_local.output -> l2tpv3.vc_"..vc_id)
      config.link(app_graph, "l2tpv3_rev.vc_"..vc_id.." -> "..vc_id.."_sink_remote.input")
      config.link(app_graph, vc_id.."_sink_remote.output -> l2tpv3_rev.vc_"..vc_id)
   end
   config.app(app_graph, "noise", SourceL2TPv3,
              { session = math.random(2^32-1),
                cookie = random_cookie() })
   config.link(app_graph, "noise.output -> join.noise")
   config.app(app_graph, "join", Join)
   config.app(app_graph, "l2tpv3", tunnel,
              { vcs = vcs,
                ancillary_data = {
                   local_addr = "::",
                   remote_addr = "::"
                } })
   config.app(app_graph, "l2tpv3_rev", tunnel, { vcs = vcs_rev })
   config.app(app_graph, "sink_rev", Sink)

   config.link(app_graph, "join.output -> l2tpv3.south")
   config.link(app_graph, "l2tpv3.south -> l2tpv3_rev.south")
   config.link(app_graph, "l2tpv3_rev.south -> sink_rev.input")

   engine.configure(app_graph)
   engine.main({ duration = 1 })

   local counter = require("core.counter")
   local function packets (app, link, dir)
      local at = engine.app_table[app]
      return tonumber(counter.read(at[dir][link].stats.rxpackets))
   end

   for vc_id = 1, nvcs do
      assert(packets(vc_id.."_remote", "output", "output") ==
                packets("l2tpv3", "vc_"..vc_id, "output"))
      assert(packets(vc_id.."_local", "output", "output") ==
                packets(vc_id.."_sink_remote", "input", "input"))
   end
end
