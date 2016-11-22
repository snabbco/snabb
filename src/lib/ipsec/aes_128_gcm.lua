module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local ASM = require("lib.ipsec.aes_128_gcm_avx")
local header = require("lib.protocol.header")
local lib = require("core.lib")
local ntohl, htonl = lib.ntohl, lib.htonl


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

-- Encrypt a single 128-bit block with the basic AES block cipher.
local function aes_128_block (block, key)
   local gcm_data = ffi.new("gcm_data __attribute__((aligned(16)))")
   ASM.aes_keyexp_128_enc_avx(key, gcm_data)
   ASM.aesni_encrypt_single_block(gcm_data, block)
end

local aes_128_gcm = {}

function aes_128_gcm:new (spi, key, salt)
   assert(spi, "Need SPI.")
   assert(key and #key == 32, "Need 16 bytes of key material.")
   assert(salt and #salt == 8, "Need 4 bytes of salt.")
   local o = {}
   o.key = ffi.new("uint8_t[16]")
   ffi.copy(o.key, lib.hexundump(key, 16), 16)
   o.IV_SIZE = 8
   o.iv = iv:new(lib.hexundump(salt, 4))
   o.AUTH_SIZE = 16
   o.auth_buf = ffi.new("uint8_t[?]", o.AUTH_SIZE)
   o.AAD_SIZE = 12
   o.aad = aad:new(spi)
   -- Compute subkey (H)
   o.hash_subkey = ffi.new("uint8_t[?] __attribute__((aligned(16)))", 16)
   aes_128_block(o.hash_subkey, o.key)
   o.gcm_data = ffi.new("gcm_data __attribute__((aligned(16)))")
   ASM.aes_keyexp_128_enc_avx(o.key, o.gcm_data)
   ASM.aesni_gcm_precomp_avx_gen4(o.gcm_data, o.hash_subkey)
   return setmetatable(o, {__index=aes_128_gcm})
end

function aes_128_gcm:encrypt (out_ptr, iv, seq_low, seq_high, payload, length, auth_dest)
   self.iv:iv(iv)
   self.aad:seq_no(seq_low, seq_high)
   ASM.aesni_gcm_enc_avx_gen4(self.gcm_data,
                              out_ptr,
                              payload, length,
                              u8_ptr(self.iv:header_ptr()),
                              u8_ptr(self.aad:header_ptr()), self.AAD_SIZE,
                              auth_dest, self.AUTH_SIZE)
end

function aes_128_gcm:decrypt (out_ptr, seq_low, seq_high, iv, ciphertext, length)
   self.iv:iv(iv)
   self.aad:seq_no(seq_low, seq_high)
   ASM.aesni_gcm_dec_avx_gen4(self.gcm_data,
                              out_ptr,
                              ciphertext, length,
                              u8_ptr(self.iv:header_ptr()),
                              u8_ptr(self.aad:header_ptr()), self.AAD_SIZE,
                              self.auth_buf, self.AUTH_SIZE)
   return C.memcmp(self.auth_buf, ciphertext + length, self.AUTH_SIZE) == 0
end


function selftest ()
   local seq_no_t = require("lib.ipsec.seq_no_t")
   -- Test decryption against vectors from “Test Cases for the use of GCM [...]
   -- in IPsec ESP”, see: https://tools.ietf.org/html/draft-mcgrew-gcm-test-01
   local test = { { key   = "4c80cdefbb5d10da906ac73c3613a634",
                    salt  = "2e443b68",
                    spi   = 0x00004321,
                    seq   = 0x8765432100000000ULL,
                    iv    = "4956ed7e3b244cfe",
                    ctag  = "fecf537e729d5b07dc30df528dd22b76"..
                            "8d1b98736696a6fd348509fa13ceac34"..
                            "cfa2436f14a3f3cf65925bf1f4a13c5d"..
                            "15b21e1884f5ff6247aeabb786b93bce"..
                            "61bc17d768fd9732459018148f6cbe72"..
                            "2fd04796562dfdb4",
                    plain = "45000048699a000080114db7c0a80102"..
                            "c0a801010a9bf15638d3010000010000"..
                            "00000000045f736970045f7564700373"..
                            "69700963796265726369747902646b00"..
                            "0021000101020201" },
                  { key   = "3de09874b388e6491988d0c3607eae1f",
                    salt  = "57690e43",
                    spi   = 0x42f67e3f,
                    seq   = 0x1010101010101010ULL,
                    iv    = "4e280000a2fca1a3",
                    ctag  = "fba2caa4853cf9f0f22cb10d86dd83b0"..
                            "fec75691cf1a04b00d1138ec9c357917"..
                            "65acbd8701ad79845bf9fe3fba487bc9"..
                            "1755e6662b4c8d0d1f5e22739530320a"..
                            "e0d731cc978ecafaeae88f00e80d6e48",
                    plain = "4500003c99c300008001cb7c40679318"..
                            "010101010800085c0200430061626364"..
                            "65666768696a6b6c6d6e6f7071727374"..
                            "75767761626364656667686901020201" },
                  { key   = "3de09874b388e6491988d0c3607eae1f",
                    salt  = "57690e43",
                    spi   = 0x42f67e3f,
                    seq   = 0x1010101010101010ULL,
                    iv    = "4e280000a2fca1a3",
                    ctag  = "fba2ca845e5df9f0f22c3e6e86dd831e"..
                            "1fc65792cd1af9130e1379ed369f071f"..
                            "35e034be95f112e4e7d05d35",
                    plain = "4500001c42a200008001441f406793b6"..
                            "e00000020a00f5ff01020201" },
                  { key   = "abbccddef00112233445566778899aab",
                    salt  = "decaf888",
                    spi   = 0x00000100,
                    seq   = 0x0000000000000001ULL,
                    iv    = "cafedebaceface74",
                    ctag  = "18a6fd42f72cbf4ab2a2ea901f73d814"..
                            "e3e7f243d95412e1c349c1d2fbec168f"..
                            "9190feebaf2cb01984e65863965d7472"..
                            "b79da345e0e780191f0d2f0e0f496c22"..
                            "6f2127b27db35724e7845d68651f57e6"..
                            "5f354f75ff17015769623436",
                    plain = "4500004933ba00007f119106c3fb1d10"..
                            "c2b1d326c02831ce0035dd7b800302d5"..
                            "00004e20001e8c18d75b81dc91baa047"..
                            "6b91b924b280389d92c963bac046ec95"..
                            "9b6266c04722b14923010101" },
                  { key   = "3de09874b388e6491988d0c3607eae1f",
                    salt  = "57690e43",
                    spi   = 0x42f67e3f,
                    seq   = 0x1010101010101010ULL,
                    iv    = "4e280000a2fca1a3",
                    ctag  = "fba2cad12fc1f9f00d3cebf305410db8"..
                            "3d7784b607323d220f24b0a97d541828"..
                            "00cadb0f68d99ef0e0c0c89ae9bea888"..
                            "4e52d65bc1afd0740f742444747b5b39"..
                            "ab533163aad4550ee5160975cdb608c5"..
                            "769189609763b8e18caa81e2",
                    plain = "45000049333e00007f119182c3fb1d10"..
                            "c2b1d326c02831ce0035cb458003025b"..
                            "000001e0001e8c18d65759d52284a035"..
                            "2c71475c8880391c764d6e5ee0496b32"..
                            "5ae270c03899493915010101" },
                  { key   = "abbccddef00112233445566778899aab",
                    salt  = "decaf888",
                    spi   = 0x00000100,
                    seq   = 0x0000000000000001ULL,
                    iv    = "cafedebaceface74",
                    ctag  = "29c9fc69a197d038ccdd14e2ddfcaa05"..
                            "43332164412503524303ed3c6c5f2838"..
                            "43af8c3e",
                    plain = "746f016265016f72016e6f7401746f01"..
                            "62650001" },
                  { key   = "3de09874b388e6491988d0c3607eae1f",
                    salt  = "57690e43",
                    spi   = 0x3f7ef642,
                    seq   = 0x1010101010101010ULL,
                    iv    = "4e280000a2fca1a3",
                    ctag  = "fba2caa8c6c5f9f0f22ca54a061210ad"..
                            "3f6e5791cf1aca210d117cec9c357917"..
                            "65acbd8701ad79845bf9fe3fba487bc9"..
                            "6321930684eecadb56912546e7a95c97"..
                            "40d7cb05",
                    plain = "45000030da3a00008001df3bc0a80005"..
                            "c0a800010800c6cd0200070061626364"..
                            "65666768696a6b6c6d6e6f7071727374"..
                            "01020201" },
                  { key   = "4c80cdefbb5d10da906ac73c3613a634",
                    salt  = "22433c64",
                    spi   = 0x00004321,
                    seq   = 0x8765432100000007ULL,
                    iv    = "4855ec7d3a234bfd",
                    ctag  = "74752e8aeb5d873cd7c0f4acc36c4bff"..
                            "84b7d7b98f0ca8b6acda6894bc619069"..
                            "ef9cbc28fe1b56a7c4e0d58c86cd2bc0",
                    plain = "0800c6cd020007006162636465666768"..
                            "696a6b6c6d6e6f707172737401020201" } }
   for i, t in ipairs(test) do
      print("Test vector:", i)
      local gcm = aes_128_gcm:new(t.spi, t.key, t.salt)
      local iv = lib.hexundump(t.iv, gcm.IV_SIZE)
      local seq = ffi.new(seq_no_t)
      seq.no = t.seq
      local length = #t.plain/2
      local p = ffi.new("uint8_t[?]", length + gcm.AUTH_SIZE)
      local c = ffi.new("uint8_t[?]", length + gcm.AUTH_SIZE)
      local o = ffi.new("uint8_t[?]", length + gcm.AUTH_SIZE)
      ffi.copy(p, lib.hexundump(t.plain, length), length)
      ffi.copy(c, lib.hexundump(t.ctag, length + gcm.AUTH_SIZE), length + gcm.AUTH_SIZE)
      gcm:encrypt(o, iv, seq:low(), seq:high(), p, length, o + length)
      print("ctext+tag", lib.hexdump(ffi.string(c, length + gcm.AUTH_SIZE)))
      print("is       ", lib.hexdump(ffi.string(o, length + gcm.AUTH_SIZE)))
      assert(C.memcmp(c, o, length + gcm.AUTH_SIZE) == 0)
      gcm:decrypt(o, seq:low(), seq:high(), iv, c, length)
      print("plaintext", lib.hexdump(ffi.string(p, length)))
      print("is       ", lib.hexdump(ffi.string(o, length)))
      assert(C.memcmp(p, o, length) == 0)
      assert(C.memcmp(c + length, o + length, gcm.AUTH_SIZE) == 0,
             "Authentication failed.")
   end
   -- Microbenchmarks.
   local length = 1000 * 1000 * 100 -- 100MB
   local gcm = aes_128_gcm:new(0x0, "00000000000000000000000000000000", "00000000")
   local p = ffi.new("uint8_t[?]", length + gcm.AUTH_SIZE)
   local start = C.get_monotonic_time()
   ASM.aesni_gcm_enc_avx_gen4(gcm.gcm_data,
                              p, p, length,
                              u8_ptr(gcm.iv:header_ptr()),
                              p, 0, -- No AAD
                              p + length, gcm.AUTH_SIZE)
   local finish = C.get_monotonic_time()
   print("Encrypted", length, "bytes in", finish-start, "seconds")
   local start = C.get_monotonic_time()
   ASM.aesni_gcm_dec_avx_gen4(gcm.gcm_data,
                              p, p, length,
                              u8_ptr(gcm.iv:header_ptr()),
                              p, 0, -- No AAD
                              p + length, gcm.AUTH_SIZE)
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
      assert(C.memcmp(should, block, 16) == 0)
   end
end


aes_128_gcm.selftest = selftest
return aes_128_gcm
