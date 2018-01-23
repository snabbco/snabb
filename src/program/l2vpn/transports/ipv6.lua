local ipv6 = require("lib.protocol.ipv6")
local packet = require("core.packet")

local transport = subClass(nil)

function transport:new (conf, tunnel_proto, logger)
   local o = transport:superClass().new(self)
   assert(conf and conf.src and conf.dst,
          "missing transport configuration")
   for _, key in ipairs({'src', 'dst'}) do
      if type(conf[key]) == "string" then
         conf[key] = ipv6:pton(conf[key])
      end
   end
   o.header = ipv6:new({ next_header = tunnel_proto,
                         hop_limit = conf.hop_limit or nil,
                         src = conf.src,
                         dst = conf.dst })
   o.peer = ipv6:ntop(conf.dst)
   o.logger = logger
   return o
end

function transport:encapsulate (datagram, tunnel_header)
   self.header:payload_length(tunnel_header:sizeof()
                                 + datagram:packet().length)
end

return transport
