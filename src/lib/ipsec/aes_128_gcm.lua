module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local ASM = require("lib.ipsec.aes_128_gcm_avx")
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
               uint8_t iv[8];
               uint32_t padding;
            } __attribute__((packed, aligned(16)))
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
      ffi.copy(h.iv, iv, 8)
   else
      return self:header_ptr()+4, 8
   end
end


-- AES-128-GCM wrapper

local function u8_ptr (ptr) return ffi.cast("uint8_t *", ptr) end

local aes_128_gcm = {}

function aes_128_gcm:new (keymat, salt)
   assert(keymat and #keymat == 32, "Need 16 bytes of key material.")
   assert(salt and #salt == 8, "Need 4 bytes of salt.")
   local o = {}
   o.keymat = ffi.new("uint8_t[16]")
   ffi.copy(o.keymat, lib.hexundump(keymat, 16), 16)
   o.iv = iv:new(lib.hexundump(salt, 4))
   -- Compute subkey (H)
   o.hash_subkey = ffi.new("uint8_t[?] __attribute__((aligned(16)))", 128)
   o.gcm_data = ffi.new("gcm_data[1] __attribute__((aligned(16)))")
   ASM.aes_keyexp_128_enc_avx(o.keymat, o.gcm_data[0].expanded_keys)
   ASM.aesni_gcm_precomp_avx_gen4(o.gcm_data, o.hash_subkey)
   o.iv_size = 8
   o.auth_size = 16
   o.auth_buf = ffi.new("uint8_t[?]", o.auth_size)
   return setmetatable(o, {__index=aes_128_gcm})
end

function aes_128_gcm:encrypt (out_ptr, iv, payload, length, esp)
   self.iv:iv(iv)
   ASM.aesni_gcm_enc_avx_gen4(self.gcm_data,
                              out_ptr,
                              payload, length,
                              u8_ptr(self.iv:header_ptr()),
                              u8_ptr(esp:header_ptr()), esp:sizeof(),
                              out_ptr + length, self.auth_size)
end

function aes_128_gcm:decrypt (out_ptr, iv, ciphertext, length, esp)
   self.iv:iv(iv)
   ASM.aesni_gcm_dec_avx_gen4(self.gcm_data,
                              out_ptr,
                              ciphertext, length,
                              u8_ptr(self.iv:header_ptr()),
                              u8_ptr(esp:header_ptr()), esp:sizeof(),
                              self.auth_buf, self.auth_size)
   return C.memcmp(self.auth_buf, ciphertext + length, self.auth_size) == 0
end


function selftest ()
   -- Test vectors (2 and 3) from McGrew, D. and J. Viega, "The Galois/Counter
   -- Mode of Operation (GCM)"
   local test = { { key        = "00000000000000000000000000000000",
                    salt       = "00000000",
                    iv         =         "0000000000000000",
                    plaintext  = "00000000000000000000000000000000",
                    ciphertext = "0388dace60b6a392f328c2b971b2fe78",
                    icv        = "58e2fccefa7e3061367f1d57a4e7455a"},
                  { key        = "feffe9928665731c6d6a8f9467308308",
                    salt       = "cafebabe",
                    iv         =         "facedbaddecaf888",
                    plaintext  = "d9313225f88406e5a55909c5aff5269a"..
                                 "86a7a9531534f7da2e4c303d8a318a72"..
                                 "1c3c0c95956809532fcf0e2449a6b525"..
                                 "b16aedf5aa0de657ba637b391aafd255",
                    ciphertext = "42831ec2217774244b7221b784d0d49c"..
                                 "e3aa212f2c02a4e035c17e2329aca12e"..
                                 "21d514b25466931c7d8f6a5aac84aa05"..
                                 "1ba30b396a0aac973d58e091473f5985",
                    icv        = "3247184b3c4f69a44dbcd22887bbb418"}, }
   for i, t in ipairs(test) do
      print("Test vector:", i)
      local gcm = aes_128_gcm:new(t.key, t.salt)
      local iv = lib.hexundump(t.iv, gcm.iv_size)
      local length = #t.plaintext/2
      local p = ffi.new("uint8_t[?]", length + gcm.auth_size)
      local c = ffi.new("uint8_t[?]", length + gcm.auth_size)
      local o = ffi.new("uint8_t[?]", length + gcm.auth_size)
      local icv = lib.hexundump(t.icv, gcm.auth_size)
      ffi.copy(p, lib.hexundump(t.plaintext, length), length)
      ffi.copy(c, lib.hexundump(t.ciphertext, length), length)
      gcm.iv:iv(iv)
      ASM.aesni_gcm_enc_avx_gen4(gcm.gcm_data,
                                 o, p, length,
                                 u8_ptr(gcm.iv:header_ptr()),
                                 iv, 0, -- No AAD
                                 o + length, gcm.auth_size)
      print("ciphertext", lib.hexdump(ffi.string(c, length)))
      print("is        ", lib.hexdump(ffi.string(o, length)))
      print("auth      ", lib.hexdump(ffi.string(icv, gcm.auth_size)))
      print("is        ", lib.hexdump(ffi.string(o + length, gcm.auth_size)))
      assert(C.memcmp(c, o, length) == 0)
      assert(C.memcmp(icv, o + length, gcm.auth_size) == 0)
      ASM.aesni_gcm_dec_avx_gen4(gcm.gcm_data,
                                 o, c, length,
                                 u8_ptr(gcm.iv:header_ptr()),
                                 iv, 0, -- No AAD
                                 o + length, gcm.auth_size)
      print("plaintext ", lib.hexdump(ffi.string(p, length)))
      print("is        ", lib.hexdump(ffi.string(o, length)))
      print("auth      ", lib.hexdump(ffi.string(icv, gcm.auth_size)))
      print("is        ", lib.hexdump(ffi.string(o + length, gcm.auth_size)))
      assert(C.memcmp(p, o, length) == 0)
      assert(C.memcmp(icv, o + length, gcm.auth_size) == 0)
   end
end


aes_128_gcm.selftest = selftest
return aes_128_gcm
