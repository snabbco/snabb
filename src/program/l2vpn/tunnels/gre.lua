local gre = require("lib.protocol.gre")
local tobit = require("bit").tobit

local tunnel = subClass(nil)
tunnel.proto = 47
tunnel.class = gre

function tunnel:new (conf, use_cc, logger)
   local o = tunnel:superClass().new(self)
   o.conf = conf
   -- 0x6558 is the protocol number assigned to "Transparent Ethernet Bridging"
   o.header = gre:new({ protocol = 0x6558,
                        checksum = conf.checksum,
                        key = conf.key })
   if conf.key ~= nil then
      -- Set key as inbound and outbound "VC Label" in MIB
      o.OutboundVcLabel = conf.key
      o.InboundVcLabel = conf.key
   end
   if use_cc then
      assert(conf.key == nil or conf.key ~= 0xFFFFFFFE,
             "Key 0xFFFFFFFE is reserved for the control channel")
      o.cc_header = gre:new({ protocol = 0x6558,
                              checksum = nil,
                              key = 0xFFFFFFFE })
   end
   -- Static protcol object used in decapsulate()
   o._proto = gre:new()
   o._logger = logger
   return o
end

function tunnel:encapsulate (datagram)
   if self.header:checksum() then
      self.header:checksum(datagram:payload())
   end
end

-- Return values status, code
-- status
--   true
--     proper VPN packet, code irrelevant
--   false
--     code
--       0 decap error -> increase error counter
--       1 control-channel packet
local function key_or_none(key)
   if key then
      return '0x'..bit.tohex(key)
   else
      return 'none'
   end
end

function tunnel:decapsulate (datagram)
   local conf = self.conf
   local code = 0
   local gre = self._proto:new_from_mem(datagram:payload())
   if gre then
      local gre_size = gre:sizeof()
      local ok = true
      if gre:checksum() ~= nil then
         local payload, length = datagram:payload()
         if not gre:checksum_check(payload + gre_size, length - gre_size) then
            ok = false
            self._logger:log("Bad GRE checksum")
         end
      end
      if ok then
         local key = gre:key()
         if ((conf.key and key and tobit(key) == tobit(conf.key)) or
          not (conf.key or key)) then
            datagram:pop_raw(gre_size)
            return true
         else
            if key and tobit(key) == tobit(0xFFFFFFFE) then
               datagram:pop_raw(gre_size)
               code = 1
            elseif self._logger:can_log() then
               self._logger:log("GRE key mismatch: local "
                                ..key_or_none(self.conf.key)
                             ..", remote "..key_or_none(gre:key()))
            end
         end
      end
   end
   return false, code
end

return tunnel
