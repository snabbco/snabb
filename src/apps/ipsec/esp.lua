-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- This app implements a point-to-point encryption tunnel using ESP with
-- AES-128-GCM.

module(..., package.seeall)
local esp = require("lib.ipsec.esp")
local counter = require("core.counter")
local C = require("ffi").C

AES128gcm = {
   config = {
      spi = {required=true},
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

function AES128gcm:new (conf)
   local self = {}
   assert(conf.transmit_salt ~= conf.receive_salt,
          "Refusing to operate with transmit_salt == receive_salt")
   self.encrypt = esp.esp_v6_encrypt:new{
      mode = "aes-128-gcm",
      spi = conf.spi,
      key = conf.transmit_key,
      salt = conf.transmit_salt}
   self.decrypt = esp.esp_v6_decrypt:new{
      mode = "aes-128-gcm",
      spi = conf.spi,
      key = conf.receive_key,
      salt = conf.receive_salt,
      window_size = conf.receive_window,
      resync_threshold = conf.resync_threshold,
      resync_attempts = conf.resync_attempts,
      auditing = conf.auditing}
   return setmetatable(self, {__index = AES128gcm})
end

function AES128gcm:push ()
   -- Encapsulation path
   local input = self.input.decapsulated
   local output = self.output.encapsulated
   for _=1,link.nreadable(input) do
      local p = link.receive(input)
      if self.encrypt:encapsulate(p) then
         link.transmit(output, p)
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
      if self.decrypt:decapsulate(p) then
         link.transmit(output, p)
      else
         packet.free(p)
         counter.add(self.shm.rxerrors)
      end
   end
end
