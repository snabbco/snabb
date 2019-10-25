-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Apps that implements point-to-point ESP tunnels in transport and tunnel mode
-- for IPv6.

module(..., package.seeall)
local esp = require("lib.ipsec.esp")
local counter = require("core.counter")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")

Transport6 = {
   config = {
      spi = {required=true},
      aead = {default="aes-gcm-16-icv"},
      transmit_key = {required=true},
      transmit_salt =  {required=true},
      receive_key = {required=true},
      receive_salt =  {required=true},
      receive_window = {},
      resync_threshold = {},
      resync_attempts = {},
      auditing = {}
   },
   shm = {
      txerrors = {counter}, rxerrors = {counter}
   }
}

function Transport6:new (conf)
   local self = {}
   assert(conf.transmit_salt ~= conf.receive_salt,
          "Refusing to operate with transmit_salt == receive_salt")
   self.encrypt = esp.encrypt:new{
      aead = conf.aead,
      spi = conf.spi,
      key = conf.transmit_key,
      salt = conf.transmit_salt}
   self.decrypt = esp.decrypt:new{
      aead = conf.aead,
      spi = conf.spi,
      key = conf.receive_key,
      salt = conf.receive_salt,
      window_size = conf.receive_window,
      resync_threshold = conf.resync_threshold,
      resync_attempts = conf.resync_attempts,
      auditing = conf.auditing}
   return setmetatable(self, {__index = Transport6})
end

function Transport6:push ()
   -- Encapsulation path
   local input = self.input.decapsulated
   local output = self.output.encapsulated
   for _=1,link.nreadable(input) do
      local p = link.receive(input)
      local p_enc = self.encrypt:encapsulate_transport6(p)
      if p_enc then
         link.transmit(output, p_enc)
      else
         packet.free(p)
         counter.add(self.shm.txerrors)
      end
   end
   -- Decapsulation path
   local input = self.input.encapsulated
   local output = self.output.decapsulated
   for _=1,link.nreadable(input) do
      local p = link.receive(input)
      local p_dec = self.decrypt:decapsulate_transport6(p)
      if p_dec then
         link.transmit(output, p_dec)
      else
         packet.free(p)
         counter.add(self.shm.rxerrors)
      end
   end
end

Tunnel6 = {
   config = {
      self_ip = {required=true},
      nexthop_ip = {required=true},
      spi = {required=true},
      aead = {default="aes-gcm-16-icv"},
      transmit_key = {required=true},
      transmit_salt =  {required=true},
      receive_key = {required=true},
      receive_salt =  {required=true},
      receive_window = {},
      resync_threshold = {},
      resync_attempts = {},
      auditing = {},
      selftest = {default=false}
   },
   shm = {
      txerrors = {counter}, rxerrors = {counter}
   },
   -- https://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml
   NextHeaderIPv6 = 41
}

function Tunnel6:new (conf)
   local self = {}
   assert(conf.selftest or conf.transmit_salt ~= conf.receive_salt,
          "Refusing to operate with transmit_salt == receive_salt")
   self.encrypt = esp.encrypt:new{
      aead = conf.aead,
      spi = conf.spi,
      key = conf.transmit_key,
      salt = conf.transmit_salt
   }
   self.decrypt = esp.decrypt:new{
      aead = conf.aead,
      spi = conf.spi,
      key = conf.receive_key,
      salt = conf.receive_salt,
      window_size = conf.receive_window,
      resync_threshold = conf.resync_threshold,
      resync_attempts = conf.resync_attempts,
      auditing = conf.auditing
   }
   self.eth = ethernet:new{
      type = 0x86dd -- IPv6
   }
   self.ip = ipv6:new{
      src = ipv6:pton(conf.self_ip),
      dst = ipv6:pton(conf.nexthop_ip),
      next_header = esp.PROTOCOL,
      hop_limit = 64
   }
   return setmetatable(self, {__index = Tunnel6})
end

function Tunnel6:push ()
   -- Encapsulation path
   local input = self.input.decapsulated
   local output = self.output.encapsulated
   while not link.empty(input) do
      local p = link.receive(input)
      if p.length >= ethernet:sizeof() then
         -- Strip Ethernet header
         p = packet.shiftleft(p, ethernet:sizeof())
         -- Encrypt payload
         local p_enc = self.encrypt:encapsulate_tunnel(p, self.NextHeaderIPv6)
         -- Slap on IPv6 and Ethernet headers
         self.ip:payload_length(p_enc.length)
         p_enc = packet.prepend(p_enc, self.ip:header(), ipv6:sizeof())
         p_enc = packet.prepend(p_enc, self.eth:header(), ethernet:sizeof())
         link.transmit(output, p_enc)
      else
         packet.free(p)
         counter.add(self.shm.txerrors)
      end
   end
   -- Decapsulation path
   local input = self.input.encapsulated
   local output = self.output.decapsulated
   while not link.empty(input) do
      local p = link.receive(input)
      if p.length >= ethernet:sizeof() + ipv6:sizeof() then
         -- Strip Ethernet and IPv6 headers
         p = packet.shiftleft(p, ethernet:sizeof() + ipv6:sizeof())
         -- Decrypt payload
         local p_dec, nh = self.decrypt:decapsulate_tunnel(p)
         if p_dec and nh == self.NextHeaderIPv6 then
            -- Slap on new Ethernet header
            p_dec = packet.prepend(p_dec, self.eth:header(), ethernet:sizeof())
            link.transmit(output, p_dec)
            goto next
         end
      end
      -- Handle error
      packet.free(p)
      counter.add(self.shm.rxerrors)
      ::next::
   end
end

function selftest ()
   -- Only testing Tunnel6 because Transport6 is mostly covered in the selftest
   -- of lib.ipsec.esp.
   local basic_apps = require("apps.basic.basic_apps")
   local c = config.new()
   config.app(c, "source", basic_apps.Source)
   config.app(c, "sink", basic_apps.Sink)
   config.app(c, "tunnel", Tunnel6, {
      self_ip = "fc00::1",
      nexthop_ip = "fc00::2",
      spi = 0xdeadbeef,
      transmit_key = "00112233445566778899AABBCCDDEEFF",
      transmit_salt = "00112233",
      receive_key = "00112233445566778899AABBCCDDEEFF",
      receive_salt = "00112233",
      auditing = true,
      selftest = true
   })
   config.link(c, "source.output -> tunnel.decapsulated")
   config.link(c, "tunnel.encapsulated -> tunnel.encapsulated")
   config.link(c, "tunnel.decapsulated -> sink.input")
   engine.configure(c)
   engine.main{duration=0.0001}
   engine.report_links()
   assert(counter.read(engine.app_table.tunnel.shm.rxerrors) == 0,
          "Decapsulation error!")
   print("OK")
end
