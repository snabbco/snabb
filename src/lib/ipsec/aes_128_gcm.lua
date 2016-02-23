module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local ASM = require("lib.ipsec.aes_128_gcm_avx")
local header = require("lib.protocol.header")
local lib = require("core.lib")
local ntohl, htonl, htonll = lib.ntohl, lib.htonl, lib.htonll


-- IV pseudo header

local iv = subClass(header)
iv._name = "iv"
iv:init({ffi.typeof[[
            struct {
               uint8_t salt[4];
               uint8_t iv[8];
               uint32_t padding;
            } __attribute__((packed, aligned(16)))
         ]]})

function iv:new (salt)
   local o = iv:superClass().new(self)
   local h = o:header()
   ffi.copy(h.salt, salt, 4)
   h.padding = htonl(0x1)
   return o
end

function iv:iv (iv)
   local h = self:header()
   if iv ~= nil then
      ffi.copy(h.iv, iv, 8)
   else
      return self:header_ptr()+4, 8
   end
end


-- AAD pseudo header

local aad = subClass(header)
aad._name = "aad"
aad:init({ffi.typeof[[
            struct {
               uint32_t spi;
               uint32_t seq_no[2];
               uint32_t padding;
            } __attribute__((packed))
          ]]})

function aad:new (spi)
   local o = aad:superClass().new(self)
   local h = o:header()
   h.spi = htonl(spi)
   return o
end

function aad:seq_no (seq_l, seq_h)
   local h = self:header()
   h.seq_no[0] = htonl(seq_h)
   h.seq_no[1] = htonl(seq_l)
end


-- AES-128-GCM wrapper

local function u8_ptr (ptr) return ffi.cast("uint8_t *", ptr) end

local function aes_128_block (block, keymat)
   -- FIXME: use AES-128 to encrypt `block' with `keymat'
end

local aes_128_gcm = {}

function aes_128_gcm:new (spi, keymat, salt)
   assert(spi, "Need SPI.")
   assert(keymat and #keymat == 32, "Need 16 bytes of key material.")
   assert(salt and #salt == 8, "Need 4 bytes of salt.")
   local o = {}
   o.keymat = ffi.new("uint8_t[16]")
   ffi.copy(o.keymat, lib.hexundump(keymat, 16), 16)
   o.iv_size = 8
   o.iv = iv:new(lib.hexundump(salt, 4))
   o.auth_size = 16
   o.auth_buf = ffi.new("uint8_t[?]", o.auth_size)
   o.aad_size = 12
   o.aad = aad:new(spi)
   -- Compute subkey (H)
   o.hash_subkey = ffi.new("uint8_t[?] __attribute__((aligned(16)))", 16)
   aes_128_block(o.hash_subkey, o.keymat)
   o.gcm_data = ffi.new("gcm_data[1] __attribute__((aligned(16)))")
   ASM.aes_keyexp_128_enc_avx(o.keymat, o.gcm_data[0].expanded_keys)
   ASM.aesni_gcm_precomp_avx_gen4(o.gcm_data, o.hash_subkey)
   return setmetatable(o, {__index=aes_128_gcm})
end

function aes_128_gcm:encrypt (out_ptr, seq_no, payload, length)
   self.iv:iv(seq_no)
   self.aad:seq_no(seq_no:low(), seq_no:high())
   ASM.aesni_gcm_enc_avx_gen4(self.gcm_data,
                              out_ptr,
                              payload, length,
                              u8_ptr(self.iv:header_ptr()),
                              u8_ptr(self.aad:header_ptr()), self.aad_size,
                              out_ptr + length, self.auth_size)
end

function aes_128_gcm:decrypt (out_ptr, seq_low, seq_high, iv, ciphertext, length)
   self.iv:iv(iv)
   self.aad:seq_no(seq_low, seq_high)
   ASM.aesni_gcm_dec_avx_gen4(self.gcm_data,
                              out_ptr,
                              ciphertext, length,
                              u8_ptr(self.iv:header_ptr()),
                              u8_ptr(self.aad:header_ptr()), self.aad_size,
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
      local gcm = aes_128_gcm:new(0x0, t.key, t.salt)
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
   -- Microbenchmarks.
   local length = 1000 * 1000 * 100 -- 100MB
   local gcm = aes_128_gcm:new(0x0, test[1].key, test[1].salt)
   local p = ffi.new("uint8_t[?]", length + gcm.auth_size)
   local start = C.get_monotonic_time()
   ASM.aesni_gcm_enc_avx_gen4(gcm.gcm_data,
                              p, p, length,
                              u8_ptr(gcm.iv:header_ptr()),
                              p, 0, -- No AAD
                              p + length, gcm.auth_size)
   local finish = C.get_monotonic_time()
   print("Encrypted", length, "bytes in", finish-start, "seconds")
   local start = C.get_monotonic_time()
   ASM.aesni_gcm_dec_avx_gen4(gcm.gcm_data,
                              p, p, length,
                              u8_ptr(gcm.iv:header_ptr()),
                              p, 0, -- No AAD
                              p + length, gcm.auth_size)
   local finish = C.get_monotonic_time()
   print("Decrypted", length, "bytes in", finish-start, "seconds")
   -- Test aes_128_block with vectors from
   -- http://www.inconteam.com/software-development/41-encryption/55-aes-test-vectors 
   local test_key = ffi.new("uint8_t[16]")
   ffi.copy(test_key, lib.hexundump("2b7e151628aed2a6abf7158809cf4f3c", 16), 16)
   local block = ffi.new("uint8_t[16]")
   local should = ffi.new("uint8_t[16]")
   local test_blocks = {
      { "6bc1bee22e409f96e93d7e117393172a", "3ad77bb40d7a3660a89ecaf32466ef97" },
      { "ae2d8a571e03ac9c9eb76fac45af8e51", "f5d3d58503b9699de785895a96fdbaaf" },
      { "30c81c46a35ce411e5fbc1191a0a52ef", "43b1cd7f598ece23881b00e3ed030688" },
      { "f69f2445df4f9b17ad2b417be66c3710", "7b0c785e27e8ad3f8223207104725dd4" }
   }
   for _, b in ipairs(test_blocks) do
      print("Block:", b[1], b[2])
      ffi.copy(block, lib.hexundump(b[1], 16), 16)
      ffi.copy(should, lib.hexundump(b[2], 16), 16)
      aes_128_block(block, test_key)
      assert(C.memcmp(should, block, length) == 0)
   end
end


aes_128_gcm.selftest = selftest
return aes_128_gcm
