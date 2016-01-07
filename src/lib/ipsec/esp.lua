module(..., package.seeall)
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local esp = require("lib.protocol.esp")
local esp_tail = require("lib.protocol.esp_tail")
local aes_128_gcm = require("lib.ipsec.aes_128_gcm")
local lib = require("core.lib")
local ffi = require("ffi")


local esp_nh = 50 -- https://tools.ietf.org/html/rfc4303#section-2
local esp_length = esp:sizeof()
local esp_tail_length = esp_tail:sizeof()

function esp_v6_new (conf)
   assert(conf.mode == "aes-128-gcm", "Only supports aes-128-gcm.")
   return { aes_128_gcm = aes_128_gcm:new(conf.keymat, conf.salt),
            seq_no = 0 }
end


local esp_v6_encrypt = {}

function esp_v6_encrypt:new (conf)
   local o = esp_v6_new(conf)
   o.pad_buf = ffi.new("uint8_t[?]", o.aes_128_gcm.blocksize-1)
   o.esp_buf = ffi.new("uint8_t[?]", o.aes_128_gcm.aad_size)
   -- Fix me https://tools.ietf.org/html/rfc4303#section-3.3.3
   o.esp = esp:new_from_mem(o.esp_buf, esp_length)
   o.esp:spi(0x0) -- Fix me, set esp:spi value.
   o.esp_tail = esp_tail:new({})
   return setmetatable(o, {__index=esp_v6_encrypt})
end

-- Return next sequence number.
function esp_v6_encrypt:next_seq_no ()
   self.seq_no = self.seq_no + 1
   return self.seq_no
end

function esp_v6_encrypt:encrypt (nh, payload, length)
   local p = packet.allocate()
   self.esp:seq_no(self:next_seq_no())
   packet.append(p, self.esp:header_ptr(), esp_length)
   packet.append(p, payload, length)
   local pad_length = self.aes_128_gcm.blocksize
      - ((length + esp_tail_length) % self.aes_128_gcm.blocksize)
   packet.append(p, self.pad_buf, pad_length)
   self.esp_tail:next_header(nh)
   self.esp_tail:pad_length(pad_length)
   packet.append(p, self.esp_tail:header_ptr(), esp_tail_length)
   packet.append(p, self.pad_buf, self.aes_128_gcm.auth_size)
   self.aes_128_gcm:encrypt(packet.data(p) + esp_length,
                            packet.data(p) + esp_length,
                            length + pad_length + esp_tail_length,
                            self.esp)
   return p
end

function esp_v6_encrypt:encapsulate (p)
   local plain = datagram:new(p, ethernet)
   local eth = plain:parse_match()
   local ip = plain:parse_match()
   local nh = ip:next_header()
   local encrypted = datagram:new(self:encrypt(nh, plain:payload()))
   local _, length = encrypted:payload()
   ip:next_header(esp_nh)
   ip:payload_length(length)
   encrypted:push(ip)
   encrypted:push(eth)
   return encrypted:packet()
end


local esp_v6_decrypt = {}

function esp_v6_decrypt:new (conf)
   local o = esp_v6_new(conf)
   o.esp_overhead_size = esp_length + o.aes_128_gcm.auth_size
   o.min_payload_length = o.aes_128_gcm.blocksize + o.esp_overhead_size
   return setmetatable(o, {__index=esp_v6_decrypt})
end

-- Verify sequence number.
function esp_v6_decrypt:check_seq_no (seq_no)
   self.seq_no = self.seq_no + 1
   return self.seq_no <= seq_no
end

function esp_v6_decrypt:decrypt (payload, length)
   if length < self.min_payload_length
      or (length - self.esp_overhead_size) % self.aes_128_gcm.blocksize ~= 0
   then return end
   local data_start = payload + esp_length
   local data_length = length - esp_length - self.aes_128_gcm.auth_size
   local esp = esp:new_from_mem(payload, esp_length)
   if self.aes_128_gcm:decrypt(data_start, data_start, data_length, esp) then
      local esp_tail_start = data_start + data_length - esp_tail_length
      local esp_tail = esp_tail:new_from_mem(esp_tail_start, esp_tail_length)
      local cleartext_length = data_length - esp_tail:pad_length() - esp_tail_length
      local p = packet.from_pointer(data_start, cleartext_length)
      return esp:seq_no(), p, esp_tail:next_header()
   end
end

function esp_v6_decrypt:decapsulate (p)
   local encrypted = datagram:new(p, ethernet)
   local eth = encrypted:parse_match()
   local ip = encrypted:parse_match()
   local decrypted = nil
   if ip:next_header() == esp_nh then
      local seq_no, payload, nh = self:decrypt(encrypted:payload())
      if payload and self:check_seq_no(seq_no) then
         local plain = datagram:new(payload)
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
   local conf = { mode = "aes-128-gcm",
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
   -- Check integrity
   local p = d:packet()
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
end
