local l2tpv3 = require("lib.protocol.keyed_ipv6_tunnel")
local tobit = require("bit").tobit

local tunnel = subClass(nil)
tunnel.proto = 115
tunnel.class = l2tpv3

function tunnel:new (conf, use_cc, logger)
   local o = tunnel:superClass().new(self)
   o.conf = conf
   -- The spec for L2TPv3 over IPv6 recommends to set the session ID
   -- to 0xffffffff for the "static 1:1 mapping" scenario.
   conf.local_session = conf.local_session or 0xffffffff
   conf.remote_session = conf.remote_session or 0xffffffff
   conf.local_cookie_baked = l2tpv3:new_cookie(conf.local_cookie)
   conf.remote_cookie_baked = l2tpv3:new_cookie(conf.remote_cookie)
   o.header = l2tpv3:new({ session_id = conf.remote_session,
                           cookie = conf.remote_cookie_baked })
   o.OutboundVcLabel = conf.local_session
   o.InboundVcLabel = conf.remote_session
   if use_cc then
      assert(conf.local_session ~= 0xFFFFFFFE and
             conf.remote_session ~= 0xFFFFFFFE,
          "Session ID 0xFFFFFFFE is reserved for the control channel")
      o.cc_header = l2tpv3:new({ session_id = 0xFFFFFFFE,
                                 cookie = conf.remote_cookie_baked })
   end
   -- Static protcol object used in decapsulate()
   o._proto = l2tpv3:new()
   o._proto_size = o._proto:sizeof()
   o._logger = logger
   return o
end

function tunnel:encapsulate ()
end

function tunnel:decapsulate (datagram)
   local code = 0
   local l2tpv3 = self._proto:new_from_mem(datagram:payload())
   if l2tpv3 then
      local session_id = l2tpv3:session_id()
      if tobit(session_id) == tobit(0xFFFFFFFE) then
         datagram:pop_raw(self._proto_size)
         code = 1
      elseif not tobit(session_id) == tobit(self.conf.local_session) then
         self._logger:log("session id mismatch: expected 0x"
                          ..bit.tohex(self.conf.local_session)
                       ..", received 0x"..bit.tohex(session_id))
      elseif l2tpv3:cookie() ~= self.conf.local_cookie_baked
         and self._logger:can_log() then
            self._logger:log("cookie mismatch, expected "
                             ..tostring(self.conf.local_cookie_baked)
                          ..", received "..tostring(l2tpv3:cookie()))
      else
         datagram:pop_raw(self._proto_size)
         return true
      end
   end
   return false, code
end

return tunnel
