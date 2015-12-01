module(..., package.seeall)
local ffi = require("ffi")
local header = require("lib.protocol.header")
local lib = require("core.lib")
local ntohl, htonl, htonll = lib.ntohl, lib.htonl, lib.htonll


-- IV pseudo header

local iv = subClass(header)

-- Class variables
iv._name = "iv"
iv:init(
   {
      [1] = ffi.typeof[[
            struct {
               uint8_t salt[4];
               uint64_t iv;
               uint32_t padding;
            } __attribute__((packed))
      ]]
   })

-- Class methods

function iv:new (salt)
   local o = iv:superClass().new(self)
   local h = o:header()
   o:salt(salt)
   h.padding = htonl(0x1)
   return o
end

-- Instance methods

function iv:salt (salt)
   local h = self:header()
   if salt ~= nil then
      ffi.copy(h.salt, salt, 4)
   else
      return h.salt
   end
end

function iv:iv (iv)
   local h = self:header()
   if iv ~= nil then
      h.iv = htonll(iv)
   else
      return self:header_ptr()+4, 8
   end
end


-- AES-128-GCM wrapper

local aes_128_gcm = {}

function aes_128_gcm:new (conf)
   assert(conf.keymat and #conf.keymat == 32, "Need 16 bytes of key material.")
   assert(conf.salt and #conf.salt == 8, "Need 4 bytes of salt.")
   local o = {}
   o.keymat = lib.hexundump(conf.keymat, 16)
   o.iv = iv:new(lib.hexundump(conf.salt, 4))
   o.blocksize = 128
   o.auth_size = 16
   o.aad_size = 16
   return setmetatable(o, {__index=aes_128_gcm})
end

function aes_128_gcm:encrypt (out_ptr, payload, length, esp)
   self.iv:iv(esp:seq_no())
   -- encrypt_in_place(self.keymat,
   --                  out_ptr,
   --                  payload, length,
   --                  self.iv:header_ptr(),
   --                  esp:header_ptr(), esp:sizeof(),
   --                  payload + length, self.auth_size)
end

function aes_128_gcm:decrypt (out_ptr, ciphertext, length, esp)
   self.iv:iv(esp:seq_no())
   -- encrypt_in_place(self.keymat,
   --                  out_ptr,
   --                  ciphertext, length,
   --                  self.iv:header_ptr(),
   --                  esp:header_ptr(), esp:sizeof(),
   --                  ciphertext + length, self.auth_size)
end

return aes_128_gcm
