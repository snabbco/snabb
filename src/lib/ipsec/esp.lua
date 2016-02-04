module(..., package.seeall)
local header = require("lib.protocol.header")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local esp = require("lib.protocol.esp")
local esp_tail = require("lib.protocol.esp_tail")
local aes_128_gcm = require("lib.ipsec.aes_128_gcm")
local seq_no_t = require("lib.ipsec.seq_no_t")
local lib = require("core.lib")
local ffi = require("ffi")


local esp_nh = 50 -- https://tools.ietf.org/html/rfc4303#section-2
local esp_size = esp:sizeof()
local esp_tail_size = esp_tail:sizeof()

function esp_v6_new (conf)
   assert(conf.mode == "aes-128-gcm", "Only supports aes-128-gcm.")
   return { aes_128_gcm = aes_128_gcm:new(conf.spi, conf.keymat, conf.salt),
            seq = ffi.new(seq_no_t),
            pad_to = 4, -- minimal padding
            d_in = datagram:new(),
            d_out = datagram:new()}
end

esp_v6_encrypt = {}

function esp_v6_encrypt:new (conf)
   local o = esp_v6_new(conf)
   o.zero_buf = ffi.new("uint8_t[?]", math.max(o.pad_to, o.aes_128_gcm.auth_size))
   o.esp = esp:new({})
   o.esp:spi(assert(conf.spi, "Need SPI."))
   o.esp_tail = esp_tail:new({})
   return setmetatable(o, {__index=esp_v6_encrypt})
end

-- Return next sequence number.
function esp_v6_encrypt:next_seq_no ()
   self.seq.no = self.seq.no + 1
   return self.seq:low()
end

local function padding (a, l) return (a - l%a) % a end

function esp_v6_encrypt:encrypt (nh, payload, length)
   local gcm = self.aes_128_gcm
   local p = packet.allocate()
   self.esp:seq_no(self:next_seq_no())
   packet.append(p, self.esp:header_ptr(), esp_size)
   packet.append(p, self.seq, gcm.iv_size)
   packet.append(p, payload, length)
   -- Padding, see https://tools.ietf.org/html/rfc4303#section-2.4
   local pad_length = padding(self.pad_to, gcm.iv_size + length + esp_tail_size)
   packet.append(p, self.zero_buf, pad_length)
   self.esp_tail:next_header(nh)
   self.esp_tail:pad_length(pad_length)
   packet.append(p, self.esp_tail:header_ptr(), esp_tail_size)
   packet.append(p, self.zero_buf, gcm.auth_size)
   local cleartext = packet.data(p) + esp_size + gcm.iv_size
   gcm:encrypt(cleartext, self.seq, cleartext, length + pad_length + esp_tail_size)
   return p
end

function esp_v6_encrypt:encapsulate (p)
   local plain = self.d_in:new(p)
   if not plain:parse({{ethernet}, {ipv6}}) then return nil end
   local eth, ip = unpack(plain:stack())
   local nh = ip:next_header()
   local encrypted = self.d_out:new(self:encrypt(nh, plain:payload()))
   local _, length = encrypted:payload()
   ip:next_header(esp_nh)
   ip:payload_length(length)
   encrypted:push(ip)
   encrypted:push(eth)
   return encrypted:packet()
end


esp_v6_decrypt = {}

function esp_v6_decrypt:new (conf)
   local o = esp_v6_new(conf)
   local gcm = o.aes_128_gcm
   local esp_overhead = esp_size + esp_tail_size + gcm.iv_size + gcm.auth_size
   o.min_size = esp_overhead + padding(o.pad_to, esp_overhead)
   o.window_size = conf.window_size or 128
   return setmetatable(o, {__index=esp_v6_decrypt})
end

-- Verify sequence number.
function esp_v6_decrypt:check_seq_no (seq_no)
   -- See https://tools.ietf.org/html/rfc4303#page-38
   -- This is a only partial implementation that attempts to keep track of the
   -- ESN counter, but does not detect replayed packets.
   local function bit32 (n) return n % 2^32 end
   local W = self.window_size
   local Tl, Th = self.seq:low(), self.seq:high()
   if Tl >= bit32(W - 1) then -- Case A
      if seq_no >= bit32(Tl - W + 1) then return seq_no, Th
      else                                return seq_no, bit32(Th + 1) end
   else                       -- Case B
      if seq_no >= bit32(Tl - W + 1) then return seq_no, bit32(Th - 1)
      else                                return seq_no, Th end
   end
end

function esp_v6_decrypt:decrypt (payload, length)
   local gcm = self.aes_128_gcm
   if length < self.min_size then return end
   local iv_start = payload + esp_size
   local data_start = payload + esp_size + gcm.iv_size
   local data_length = length - esp_size - gcm.iv_size - gcm.auth_size
   local esp = esp:new_from_mem(payload, esp_size)
   local seq_low, seq_high = self:check_seq_no(esp:seq_no())
   if seq_low and gcm:decrypt(data_start, seq_low, seq_high, iv_start, data_start, data_length) then
      local esp_tail_start = data_start + data_length - esp_tail_size
      local esp_tail = esp_tail:new_from_mem(esp_tail_start, esp_tail_size)
      local cleartext_length = data_length - esp_tail:pad_length() - esp_tail_size
      local p = packet.from_pointer(data_start, cleartext_length)
      self.seq:low(seq_low)
      self.seq:high(seq_high)
      return p, esp_tail:next_header()
   end
end

function esp_v6_decrypt:decapsulate (p)
   local encrypted = self.d_in:new(p)
   if not encrypted:parse({{ethernet}, {ipv6}}) then return nil end
   local eth, ip = unpack(encrypted:stack())
   if ip:next_header() == esp_nh then
      local payload, nh = self:decrypt(encrypted:payload())
      if payload then
         local plain = self.d_out:new(payload)
         ip:next_header(nh)
         ip:payload_length(packet.length(payload))
         plain:push(ip)
         plain:push(eth)
         return plain:packet()
      end
   end
end


function selftest ()
   local C = require("ffi").C
   local ipv6 = require("lib.protocol.ipv6")
   local conf = { spi = 0x0,
                  mode = "aes-128-gcm",
                  keymat = "00112233445566778899AABBCCDDEEFF",
                  salt = "00112233"}
   local enc, dec = esp_v6_encrypt:new(conf), esp_v6_decrypt:new(conf)
   local payload = packet.from_string(
[[abcdefghijklmnopqrstuvwxyz
ABCDEFGHIJKLMNOPQRSTUVWXYZ
0123456789]]
   )
   local d = datagram:new(payload)
   local ip = ipv6:new({})
   ip:payload_length(packet.length(payload))
   d:push(ip)
   d:push(ethernet:new({type=0x86dd}))
   local p = d:packet()
   -- Check integrity
   print("original", lib.hexdump(ffi.string(packet.data(p), packet.length(p))))
   local p_enc = enc:encapsulate(packet.clone(p))
   print("encrypted", lib.hexdump(ffi.string(packet.data(p_enc), packet.length(p_enc))))
   local p2 = dec:decapsulate(p_enc)
   print("decrypted", lib.hexdump(ffi.string(packet.data(p2), packet.length(p2))))
   if p2 and p2.length == p.length and C.memcmp(p, p2, p.length) == 0 then
      print("selftest passed")
   else
      print("integrity check failed")
      os.exit(1)
   end
   -- Check transmitted Sequence Number wrap around
   enc.seq:low(0)
   enc.seq:high(1)
   dec.seq:low(2^32 - dec.window_size)
   dec.seq:high(0)
   assert(dec:decapsulate(enc:encapsulate(packet.clone(p))),
          "Transmitted Sequence Number wrap around failed.")
   assert(dec.seq:high() == 1 and dec.seq:low() == 1,
          "Lost Sequence Number synchronization.")
   -- Check Sequence Number exceeding window
   enc.seq:low(0)
   enc.seq:high(1)
   dec.seq:low(dec.window_size+1)
   dec.seq:high(1)
   assert(not dec:decapsulate(enc:encapsulate(packet.clone(p))),
          "Accepted out of window Sequence Number.")
   assert(dec.seq:high() == 1 and dec.seq:low() == dec.window_size+1,
          "Corrupted Sequence Number.")
end
