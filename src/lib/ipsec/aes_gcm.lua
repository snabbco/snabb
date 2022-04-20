-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local ASM = require("lib.ipsec.aes_gcm_avx")
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

local aes_gcm = {}

function aes_gcm:new (spi, key, keylen, salt)
   assert(spi, "Need SPI.")
   local o = {}
   if keylen == 128 then
      key = lib.hexundump(key, 16, "Need 16 bytes of key material.")
   elseif keylen == 256 then
      key = lib.hexundump(key, 32, "Need 32 bytes of key material.")
   else error("NYI") end
   o.IV_SIZE = 8
   o.iv = iv:new(lib.hexundump(salt, 4, "Need 4 bytes of salt."))
   -- “Implementations MUST support a full-length 16-octet ICV”
   o.AUTH_SIZE = 16
   o.auth_buf = ffi.new("uint8_t[?]", o.AUTH_SIZE)
   o.AAD_SIZE = 12
   o.aad = aad:new(spi)
   -- Compute subkey (H)
   local hash_subkey = ffi.new("uint8_t[16]")
   o.gcm_data = ffi.new("gcm_data __attribute__((aligned(16)))")
   if keylen == 128 then
      ASM.aes_keyexp_128_enc_avx(key, o.gcm_data)
      ASM.aesni_encrypt_128_single_block(o.gcm_data, hash_subkey)
      o.gcm_enc = ASM.aesni_gcm_enc_128_avx_gen4
      o.gcm_dec = ASM.aesni_gcm_dec_128_avx_gen4
   elseif keylen == 256 then
      ASM.aes_keyexp_256_enc_avx(key, o.gcm_data)
      ASM.aesni_encrypt_256_single_block(o.gcm_data, hash_subkey)
      o.gcm_enc = ASM.aesni_gcm_enc_256_avx_gen4
      o.gcm_dec = ASM.aesni_gcm_dec_256_avx_gen4
   end
   ASM.aesni_gcm_precomp_avx_gen4(o.gcm_data, hash_subkey)
   return setmetatable(o, {__index=aes_gcm})
end

function aes_gcm:encrypt (out_ptr, iv, seq_low, seq_high, payload, length, auth_dest)
   self.iv:iv(iv)
   self.aad:seq_no(seq_low, seq_high)
   self.gcm_enc(self.gcm_data,
                out_ptr,
                payload, length,
                u8_ptr(self.iv:header_ptr()),
                u8_ptr(self.aad:header_ptr()), self.AAD_SIZE,
                auth_dest or self.auth_buf, self.AUTH_SIZE)
end

function aes_gcm:decrypt (out_ptr, seq_low, seq_high, iv, ciphertext, length)
   self.iv:iv(iv)
   self.aad:seq_no(seq_low, seq_high)
   self.gcm_dec(self.gcm_data,
                out_ptr,
                ciphertext, length,
                u8_ptr(self.iv:header_ptr()),
                u8_ptr(self.aad:header_ptr()), self.AAD_SIZE,
                self.auth_buf, self.AUTH_SIZE)
   return ASM.auth16_equal(self.auth_buf, ciphertext + length) == 0
end

aes_128_gcm = {}
function aes_128_gcm:new (spi, key, salt)
   return aes_gcm:new(spi, key, 128, salt)
end

aes_256_gcm = {}
function aes_256_gcm:new (spi, key, salt)
   return aes_gcm:new(spi, key, 256, salt)
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
                            "696a6b6c6d6e6f707172737401020201" },
                  { key   = "abbccddef00112233445566778899aab"..
                            "abbccddef00112233445566778899aab",
                    keylen = 256,
                    salt  = "73616c74",
                    spi   = 0x17405e67,
                    seq   = 0x156f3126dd0db99bULL,
                    iv    = "616e640169766563",
                    ctag  = "f2d69ecdbd5a0d5b8d5ef38bad4da58d"..
                            "1f278fde98ef67549d524a3018d9a57f"..
                            "f4d3a31ce673119e451626c2415771e3"..
                            "b7eebca614c89b35",
                    plain = "45080028732c00004006e9f90a010612"..
                            "0a01038f06b88023dd6bafbecb712602"..
                            "50101f646d540001" },
                  { key   = "abbccddef00112233445566778899aab"..
                            "abbccddef00112233445566778899aab",
                    keylen = 256,
                    salt  = "73616c74",
                    spi   = 0x17405e67,
                    seq   = 0x156f3126dd0db99bULL,
                    iv    = "616e640169766563",
                    ctag  = "d4b7ed86a1777f2ea13d6973d324c69e"..
                            "7b43f826fb56831226508bebd2dceb18"..
                            "d0a6df10e5487df074113e14c641024e"..
                            "3e6773d91a62ee429b043a10e3efe6b0"..
                            "12a49363412364f8c0cac587f249e56b"..
                            "11e24f30e44ccc76",
                    plain = "636973636f0172756c65730174686501"..
                            "6e6574776501646566696e6501746865"..
                            "746563686e6f6c6f6769657301746861"..
                            "7477696c6c01646566696e65746f6d6f"..
                            "72726f7701020201" },
                  { key   = "6c6567616c697a656d6172696a75616e"..
                            "61616e64646f69746265666f72656961",
                    keylen = 256,
                    salt  = "7475726e",
                    spi   = 0x796b6963,
                    seq   = 0xffffffffffffffffULL,
                    iv    = "333021696765746d",
                    ctag  = "f97ab2aa356d8edce17644ac8c78e25d"..
                            "d24dedbb29ebf1b64a274b39b49c3a86"..
                            "4cd3d78ca4ae68a32b42458fb57dbe82"..
                            "1dcc63b9d0937ba2945f669368661a32"..
                            "9fb4c053",
                    plain = "45000030da3a00008001df3bc0a80005"..
                            "c0a800010800c6cd0200070061626364"..
                            "65666768696a6b6c6d6e6f7071727374"..
                            "01020201" },
   }
   for i, t in ipairs(test) do
      print("Test vector:", i)
      local gcm = aes_gcm:new(t.spi, t.key, t.keylen or 128, t.salt)
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
   -- Test extended AAD. Test vectors from NIST.
   local test = {
      { key = "2fb45e5b8f993a2bfebc4b15b533e0b4",
        iv = "5b05755f984d2b90f94b8027",
        aad = "e85491b2202caf1d7dce03b97e09331c32473941",
        plaintext = "",
        ciphertext = "",
        tag = "c75b7832b2a2d9bd827412b6ef5769db" },
      { key = "77be63708971c4e240d1cb79e8d77feb",
        iv = "e0e00f19fed7ba0136a797f3",
        aad = "7a43ec1d9c0a5a78a0b16533a6213cab",
        plaintext = "",
        ciphertext = "",
        tag = "209fcc8d3675ed938e9c7166709dd946" },
      { key = "c939cc13397c1d37de6ae0e1cb7c423c",
        iv = "b3d8cc017cbb89b39e0f67e2",
        plaintext = "c3b3c41f113a31b73d9a5cd432103069",
        aad = "24825602bd12a984e0092d3e448eda5f",
        ciphertext = "93fe7d9e9bfd10348a5606e5cafa7354",
        tag = "0032a1dc85f1c9786925a2e71d8272dd" },
      { key = "feffe9928665731c6d6a8f9467308308",
        plaintext = "d9313225f88406e5a55909c5aff5269a"..
                    "86a7a9531534f7da2e4c303d8a318a72"..
                    "1c3c0c95956809532fcf0e2449a6b525"..
                    "b16aedf5aa0de657ba637b39",
        aad = "feedfacedeadbeeffeedfacedeadbeefabaddad2",
        iv = "cafebabefacedbaddecaf888",
        ciphertext = "42831ec2217774244b7221b784d0d49c"..
                     "e3aa212f2c02a4e035c17e2329aca12e"..
                     "21d514b25466931c7d8f6a5aac84aa05"..
                     "1ba30b396a0aac973d58e091",
        tag = "5bc94fbc3221a5db94fae95ae7121a47" },
      { key = "5b9604fe14eadba931b0ccf34843dab9",
        iv = "921d2507fa8007b7bd067d34",
        aad = "00112233445566778899aabbccddeeff",
        plaintext = "001d0c231287c1182784554ca3a21908",
        ciphertext = "49d8b9783e911913d87094d1f63cc765",
        tag = "1e348ba07cca2cf04c618cb4d43a5b92" }
   }
   for i, t in ipairs(test) do      
      print("Generic test vector:", i)
      local gcm_data = ffi.new("gcm_data __attribute__((aligned(16)))")
      ASM.aes_keyexp_128_enc_avx(lib.hexundump(t.key, #t.key/2), gcm_data)
      local hash_subkey = ffi.new("uint8_t[16]")
      ASM.aesni_encrypt_128_single_block(gcm_data, hash_subkey)
      ASM.aesni_gcm_precomp_avx_gen4(gcm_data, hash_subkey)
      local aad = ffi.new("uint8_t[16]")
      local buf = ffi.new("uint8_t[?]", #t.plaintext/2)
      local iv = ffi.new("uint8_t[16] __attribute__((aligned(16)))",
                         {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1})
      local tag = ffi.new("uint8_t[16]")
      ASM.aad_prehash(gcm_data, aad, lib.hexundump(t.aad, #t.aad/2), #t.aad/2)
      ffi.copy(iv, lib.hexundump(t.iv, #t.iv/2))
      ASM.aesni_gcm_enc_128_avx_gen4(
         gcm_data,
         buf, lib.hexundump(t.plaintext, #t.plaintext/2), #t.plaintext/2,
         iv, aad, #t.aad/2, tag, 16
      )
      print("ctext", lib.hexdump(ffi.string(buf, ffi.sizeof(buf))))
      print("tag", lib.hexdump(ffi.string(tag, 16)))
      assert(ffi.string(buf, ffi.sizeof(buf)) == lib.hexundump(t.ciphertext, #t.ciphertext/2))
      assert(ffi.string(tag, 16) == lib.hexundump(t.tag, #t.tag/2))
      ASM.aesni_gcm_dec_128_avx_gen4(
         gcm_data,
         buf, buf, ffi.sizeof(buf),
         iv, aad, #t.aad/2, tag, 16
      )
      print("ptext", lib.hexdump(ffi.string(buf, ffi.sizeof(buf))))
      print("tag", lib.hexdump(ffi.string(tag, 16)))
      assert(ffi.string(buf, ffi.sizeof(buf)) == lib.hexundump(t.plaintext, #t.plaintext/2))
      assert(ffi.string(tag, 16) == lib.hexundump(t.tag, #t.tag/2))
   end
   -- Microbenchmarks.
   local pmu = require("lib.pmu")
   local has_pmu_counters, err = pmu.is_available()
   if not has_pmu_counters then
      io.stderr:write('No PMU available: '..err..'\n')
   else
      pmu.setup()
   end
   local profile = (has_pmu_counters and pmu.profile) or function (f) f() end
   local length = 1000 * 1000 * 100 -- 100MB
   local k = "00000000000000000000000000000000"..
             "00000000000000000000000000000000"
   for _, keylen in ipairs{128, 256} do
      print("AES", keylen)
      local gcm = aes_gcm:new(0x0, k, keylen, "00000000")
      local p = ffi.new("uint8_t[?]", length + gcm.AUTH_SIZE)
      local start = C.get_monotonic_time()
      profile(function ()
            gcm:encrypt(p, u8_ptr(gcm.iv:header_ptr()), 0, 0,
                        p, length, p + length)
      end)
      local finish = C.get_monotonic_time()
      print("Encrypted", length, "bytes in", finish-start, "seconds")
      local start = C.get_monotonic_time()
      profile(function ()
            gcm:decrypt(p, 0, 0, u8_ptr(gcm.iv:header_ptr()), p, length)
      end)
      local finish = C.get_monotonic_time()
      print("Decrypted", length, "bytes in", finish-start, "seconds")
   end
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
      local gcm_data = ffi.new("gcm_data __attribute__((aligned(16)))")
      ASM.aes_keyexp_128_enc_avx(test_key, gcm_data)
      ASM.aesni_encrypt_128_single_block(gcm_data, block)
      assert(C.memcmp(should, block, 16) == 0)
   end
   -- Test aes_256_block with test vectors from
   -- https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/aes-development/rijndael-vals.zip
   local key = ffi.new("uint8_t[32]")
   local pt = ffi.new("uint8_t[16]")
   local should = ffi.new("uint8_t[16]")
   local test_blocks = {
      "E35A6DCB19B201A01EBCFA8AA22B5759",
      "5075C2405B76F22F553488CAE47CE90B",
      "49DF95D844A0145A7DE01C91793302D3",
      "E7396D778E940B8418A86120E5F421FE",
      "05F535C36FCEDE4657BE37F4087DB1EF",
      "D0C1DDDD10DA777C68AB36AF51F2C204",
      "1C55FB811B5C6464C4E5DE1535A75514",
      "52917F3AE957D5230D3A2AF57C7B5A71"
   }
   for i, b in ipairs(test_blocks) do
      print("Block I=", i, b)
      key[0] = bit.rshift(0x100, i)
      ffi.fill(pt, ffi.sizeof(pt))
      ffi.copy(should, lib.hexundump(b, 16), 16)
      local gcm_data = ffi.new("gcm_data __attribute__((aligned(16)))")
      ASM.aes_keyexp_256_enc_avx(key, gcm_data)
      ASM.aesni_encrypt_256_single_block(gcm_data, pt)
      assert(C.memcmp(should, pt, 16) == 0)
   end
end
