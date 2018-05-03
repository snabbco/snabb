-- Implementation of IPsec ESP using AES-128-GCM with a 12 byte ICV and
-- “Extended Sequence Number” (see RFC 4303 and RFC 4106). Provides
-- address-family independent encapsulation/decapsulation routines for
-- “tunnel mode” and “transport mode” routines for IPv6.
--
-- Notes:
--
--  * Wrapping around of the Extended Sequence Number is *not* detected because
--    it is assumed to be an unrealistic scenario as it would take 584 years to
--    overflow the counter when transmitting 10^9 packets per second.
--
--  * decapsulate_transport6: Rejection of IP fragments is *not* implemented
--    because `lib.protocol.ipv6' does not support fragmentation. E.g.
--    fragments will be rejected because they can not be parsed as IPv6
--    packets. If however `lib.protocol.ipv6' were to be updated to be able to
--    parse IP fragments this implementation would have to be updated as well
--    to remain correct. See the “Reassembly” section of RFC 4303 for details:
--    https://tools.ietf.org/html/rfc4303#section-3.4.1
--
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
local C = ffi.C
local logger = lib.logger_new({ rate = 32, module = 'esp' })

require("lib.ipsec.track_seq_no_h")
local window_t = ffi.typeof("uint8_t[?]")

PROTOCOL = 50 -- https://tools.ietf.org/html/rfc4303#section-2

local ETHERNET_SIZE = ethernet:sizeof()
local IPV6_SIZE = ipv6:sizeof()
local ESP_SIZE = esp:sizeof()
local ESP_TAIL_SIZE = esp_tail:sizeof()

local TRANSPORT6_PAYLOAD_OFFSET = ETHERNET_SIZE + IPV6_SIZE

local function padding (a, l) return (a - l%a) % a end

function esp_new (conf)
   assert(conf.mode == "aes-gcm-128-12", "Only supports 'aes-gcm-128-12'.")
   assert(conf.spi, "Need SPI.")

   local o = {
      cipher = aes_128_gcm:new(conf.spi, conf.key, conf.salt),
      spi = conf.spi,
      seq = ffi.new(seq_no_t),
      pad_to = 4, -- minimal padding
      esp = esp:new({}),
      esp_tail = esp_tail:new({}),
      ip = ipv6:new({}) -- for transport mode
   }

   o.ESP_CTEXT_OVERHEAD = o.cipher.IV_SIZE + ESP_TAIL_SIZE
   o.ESP_OVERHEAD = ESP_SIZE + o.ESP_CTEXT_OVERHEAD + o.cipher.AUTH_SIZE

   return o
end

encrypt = {}

function encrypt:new (conf)
   return setmetatable(esp_new(conf), {__index=encrypt})
end

-- Increment sequence number.
function encrypt:next_seq_no ()
   self.seq.no = self.seq.no + 1
end

function encrypt:padding (length)
   -- See https://tools.ietf.org/html/rfc4303#section-2.4
   return padding(self.pad_to, length + self.ESP_CTEXT_OVERHEAD)
end

function encrypt:encode_esp_trailer (ptr, next_header, pad_length)
   self.esp_tail:new_from_mem(ptr, ESP_TAIL_SIZE)
   self.esp_tail:next_header(next_header)
   self.esp_tail:pad_length(pad_length)
end

function encrypt:encrypt_payload (ptr, length)
   self:next_seq_no()
   local seq, low, high = self.seq, self.seq:low(), self.seq:high()
   self.cipher:encrypt(ptr, seq, low, high, ptr, length, ptr + length)
end

function encrypt:encode_esp_header (ptr)
   self.esp:new_from_mem(ptr, ESP_SIZE)
   self.esp:spi(self.spi)
   self.esp:seq_no(self.seq:low())
   ffi.copy(ptr + ESP_SIZE, self.seq, self.cipher.IV_SIZE)
end

-- Encapsulation in transport mode is performed as follows:
--   1. Grow p to fit ESP overhead
--   2. Append ESP trailer to p
--   3. Encrypt payload+trailer in place
--   4. Move resulting ciphertext to make room for ESP header
--   5. Write ESP header
function encrypt:encapsulate_transport6 (p)
   if p.length < TRANSPORT6_PAYLOAD_OFFSET then return nil end

   local payload = p.data + TRANSPORT6_PAYLOAD_OFFSET
   local payload_length = p.length - TRANSPORT6_PAYLOAD_OFFSET
   local pad_length = self:padding(payload_length)
   local overhead = self.ESP_OVERHEAD + pad_length
   p = packet.resize(p, p.length + overhead)

   self.ip:new_from_mem(p.data + ETHERNET_SIZE, IPV6_SIZE)

   local tail = payload + payload_length + pad_length
   self:encode_esp_trailer(tail, self.ip:next_header(), pad_length)

   local ctext_length = payload_length + pad_length + ESP_TAIL_SIZE
   self:encrypt_payload(payload, ctext_length)

   local ctext = payload + ESP_SIZE + self.cipher.IV_SIZE
   C.memmove(ctext, payload, ctext_length + self.cipher.AUTH_SIZE)

   self:encode_esp_header(payload)

   self.ip:next_header(PROTOCOL)
   self.ip:payload_length(payload_length + overhead)

   return p
end

-- Encapsulation in tunnel mode is performed as follows:
-- (In tunnel mode, the input packet must be an IP frame already stripped of
-- its Ethernet header.)
--   1. Grow and shift p to fit ESP overhead
--   2. Append ESP trailer to p
--   3. Encrypt payload+trailer in place
--   4. Write ESP header
-- (The resulting packet contains the raw ESP frame, without IP or Ethernet
-- headers.)
function encrypt:encapsulate_tunnel (p, next_header)
   local pad_length = self:padding(p.length)
   local trailer_overhead = pad_length + ESP_TAIL_SIZE + self.cipher.AUTH_SIZE
   local orig_length = p.length
   p = packet.resize(p, orig_length + trailer_overhead)

   local tail = p.data + orig_length + pad_length
   self:encode_esp_trailer(tail, next_header, pad_length)

   local ctext_length = orig_length + pad_length + ESP_TAIL_SIZE
   self:encrypt_payload(p.data, ctext_length)

   local len = p.length
   p = packet.shiftright(p, ESP_SIZE + self.cipher.IV_SIZE)

   self:encode_esp_header(p.data)

   return p
end


decrypt = {}

function decrypt:new (conf)
   local o = esp_new(conf)

   o.MIN_SIZE = o.ESP_OVERHEAD + padding(o.pad_to, o.ESP_OVERHEAD)
   o.CTEXT_OFFSET = ESP_SIZE + o.cipher.IV_SIZE
   o.PLAIN_OVERHEAD = ESP_SIZE + o.cipher.IV_SIZE + o.cipher.AUTH_SIZE

   local window_size = conf.window_size or 128
   o.window_size = window_size + padding(8, window_size)
   o.window = ffi.new(window_t, o.window_size / 8)

   o.resync_threshold = conf.resync_threshold or 1024
   o.resync_attempts = conf.resync_attempts or 8

   o.decap_fail = 0

   o.auditing = conf.auditing

   return setmetatable(o, {__index=decrypt})
end

function decrypt:decrypt_payload (ptr, length)
   -- NB: bounds check is performed by caller
   local esp = self.esp:new_from_mem(ptr, esp:sizeof())
   local iv_start = ptr + ESP_SIZE
   local ctext_start = ptr + self.CTEXT_OFFSET
   local ctext_length = length - self.PLAIN_OVERHEAD

   local seq_low = esp:seq_no()
   local seq_high = tonumber(
      C.check_seq_no(seq_low, self.seq.no, self.window, self.window_size)
   )

   local error = nil
   if seq_high < 0 or not self.cipher:decrypt(
      ctext_start, seq_low, seq_high, iv_start, ctext_start, ctext_length
   ) then
      if seq_high < 0 then error = "replayed"
      else                 error = "integrity error" end

      self.decap_fail = self.decap_fail + 1
      if self.decap_fail > self.resync_threshold then
         seq_high = self:resync(ptr, length, seq_low, seq_high)
         if seq_high then error = nil end
      end
   end

   if error then
      self:audit(error)
      return nil
   end

   self.decap_fail = 0
   self.seq.no = C.track_seq_no(
      seq_high, seq_low, self.seq.no, self.window, self.window_size
   )

   local esp_tail_start = ctext_start + ctext_length - ESP_TAIL_SIZE
   self.esp_tail:new_from_mem(esp_tail_start, ESP_TAIL_SIZE)

   local ptext_length =
      ctext_length - self.esp_tail:pad_length() - ESP_TAIL_SIZE
   return ctext_start, ptext_length
end

-- Decapsulation in transport mode is performed as follows:
--   1. Parse IP and ESP headers and check Sequence Number
--   2. Decrypt ciphertext in place
--   3. Parse ESP trailer and update IP header
--   4. Move cleartext up to IP payload
--   5. Shrink p by ESP overhead
function decrypt:decapsulate_transport6 (p)
   if p.length - TRANSPORT6_PAYLOAD_OFFSET < self.MIN_SIZE then return nil end

   self.ip:new_from_mem(p.data + ETHERNET_SIZE, IPV6_SIZE)

   local payload = p.data + TRANSPORT6_PAYLOAD_OFFSET
   local payload_length = p.length - TRANSPORT6_PAYLOAD_OFFSET

   local ptext_start, ptext_length =
      self:decrypt_payload(payload, payload_length)

   if not ptext_start then return nil end

   self.ip:next_header(self.esp_tail:next_header())
   self.ip:payload_length(ptext_length)

   C.memmove(payload, ptext_start, ptext_length)
   p = packet.resize(p, TRANSPORT6_PAYLOAD_OFFSET + ptext_length)

   return p
end

-- Decapsulation in tunnel mode is performed as follows:
-- (In tunnel mode, the input packet must be already stripped of its outer
-- Ethernet and IP headers.)
--   1. Parse ESP header and check Sequence Number
--   2. Decrypt ciphertext in place
--   3. Parse ESP trailer and shrink p by overhead
-- (The resulting packet contains the raw ESP payload (i.e. an IP frame),
-- without an Ethernet header.)
function decrypt:decapsulate_tunnel (p)
   if p.length < self.MIN_SIZE then return nil end

   local ptext_start, ptext_length = self:decrypt_payload(p.data, p.length)

   if not ptext_start then return nil end

   p = packet.shiftleft(p, self.CTEXT_OFFSET)
   p = packet.resize(p, ptext_length)

   return p, self.esp_tail:next_header()
end

function decrypt:audit (reason)
   if not self.auditing then return end
   -- This is the information RFC4303 says we SHOULD log
   logger:log("Rejecting packet (" ..
              "SPI=" .. self.spi .. ", " ..
              "src_addr='" .. self.ip:ntop(self.ip:src()) .. "', " ..
              "dst_addr='" .. self.ip:ntop(self.ip:dst()) .. "', " ..
              "seq_low=" .. self.esp:seq_no() .. ", " ..
              "flow_id=" .. self.ip:flow_label() .. ", " ..
              "reason='" .. reason .. "'" ..
              ")")
end

function decrypt:resync (ptr, length, seq_low, seq_high)
   local iv_start = ptr + ESP_SIZE
   local ctext_start = ptr + self.CTEXT_OFFSET
   local ctext_length = length - self.PLAIN_OVERHEAD

   if seq_high < 0 then
      -- The sequence number looked replayed, we use the last seq_high we have
      -- seen
      seq_high = self.seq:high()
   else
      -- We failed to decrypt in-place, undo the damage to recover the original
      -- ctext (ignore bogus auth data)
      self.cipher:encrypt(
         ctext_start, iv_start, seq_low, seq_high, ctext_start, ctext_length
      )
   end

   local p_orig = packet.from_pointer(ptr, length)
   for i = 1, self.resync_attempts do
      seq_high = seq_high + 1
      if self.cipher:decrypt(
         ctext_start, seq_low, seq_high, iv_start, ctext_start, ctext_length
      ) then
         packet.free(p_orig)
         return seq_high
      else
         ffi.copy(ptr, p_orig.data, length)
      end
   end
end


function selftest ()
   local conf = { spi = 0x0,
                  mode = "aes-gcm-128-12",
                  key = "00112233445566778899AABBCCDDEEFF",
                  salt = "00112233",
                  resync_threshold = 16,
                  resync_attempts = 8}
   local enc, dec = encrypt:new(conf), decrypt:new(conf)
   local payload = packet.from_string(
[[abcdefghijklmnopqrstuvwxyz
ABCDEFGHIJKLMNOPQRSTUVWXYZ
0123456789]]
   )
   local d = datagram:new(payload)
   local ip = ipv6:new({})
   ip:payload_length(payload.length)
   d:push(ip)
   d:push(ethernet:new({type=0x86dd}))
   local p = d:packet()
   -- Check integrity
   print("original", lib.hexdump(ffi.string(p.data, p.length)))
   local p_enc = assert(enc:encapsulate_transport6(packet.clone(p)),
                        "encapsulation failed")
   print("encrypted", lib.hexdump(ffi.string(p_enc.data, p_enc.length)))
   local p2 = assert(dec:decapsulate_transport6(packet.clone(p_enc)),
                     "decapsulation failed")
   print("decrypted", lib.hexdump(ffi.string(p2.data, p2.length)))
   assert(p2.length == p.length and C.memcmp(p.data, p2.data, p.length) == 0,
          "integrity check failed")
   -- ... for tunnel mode
   local p_enc = assert(enc:encapsulate_tunnel(packet.clone(p), 42),
                        "encapsulation failed")
   print("enc. (tun)", lib.hexdump(ffi.string(p_enc.data, p_enc.length)))
   local p2, nh = dec:decapsulate_tunnel(packet.clone(p_enc))
   assert(p2 and nh == 42, "decapsulation failed")
   print("dec. (tun)", lib.hexdump(ffi.string(p2.data, p2.length)))
   assert(p2.length == p.length and C.memcmp(p.data, p2.data, p.length) == 0,
          "integrity check failed")
   -- Check invalid packets.
   assert(not enc:encapsulate_transport6(packet.from_string("invalid")),
          "encapsulated invalid packet")
   assert(not dec:decapsulate_transport6(packet.from_string("invalid")),
          "decapsulated invalid packet")
   -- ... for tunnel mode
   assert(not dec:decapsulate_tunnel(packet.from_string("invalid")),
          "decapsulated invalid packet")
   -- Check minimum packet.
   local p_min = packet.from_string("012345678901234567890123456789012345678901234567890123")
   p_min.data[18] = 0 -- Set IPv6 payload length to zero
   p_min.data[19] = 0 -- ...
   assert(p_min.length == TRANSPORT6_PAYLOAD_OFFSET)
   print("original", lib.hexdump(ffi.string(p_min.data, p_min.length)))
   local e_min = assert(enc:encapsulate_transport6(packet.clone(p_min)))
   print("encrypted", lib.hexdump(ffi.string(e_min.data, e_min.length)))
   assert(e_min.length == dec.MIN_SIZE+TRANSPORT6_PAYLOAD_OFFSET)
   e_min = assert(dec:decapsulate_transport6(e_min),
                  "decapsulation of minimum packet failed")
   print("decrypted", lib.hexdump(ffi.string(e_min.data, e_min.length)))
   assert(e_min.length == TRANSPORT6_PAYLOAD_OFFSET)
   assert(p_min.length == e_min.length
          and C.memcmp(p_min.data, e_min.data, p_min.length) == 0,
          "integrity check failed")
   -- ... for tunnel mode
   print("original", "(empty)")
   local e_min = assert(enc:encapsulate_tunnel(packet.allocate(), 0))
   print("enc. (tun)", lib.hexdump(ffi.string(e_min.data, e_min.length)))
   e_min = assert(dec:decapsulate_tunnel(e_min))
   assert(e_min.length == 0)
   -- Tunnel/transport mode independent tests
   for _, op in ipairs(
      {{encap=function (p) return enc:encapsulate_transport6(p) end,
        decap=function (p) return dec:decapsulate_transport6(p) end},
       {encap=function (p) return enc:encapsulate_tunnel(p, 0) end,
        decap=function (p) return dec:decapsulate_tunnel(p) end}}
   ) do
      -- Check transmitted Sequence Number wrap around
      C.memset(dec.window, 0, dec.window_size / 8) -- clear window
      enc.seq.no = 2^32 - 1 -- so next encapsulated will be seq 2^32
      dec.seq.no = 2^32 - 1 -- pretend to have seen 2^32-1
      local px = op.encap(packet.clone(p))
      assert(op.decap(px),
             "Transmitted Sequence Number wrap around failed.")
      assert(dec.seq:high() == 1 and dec.seq:low() == 0,
             "Lost Sequence Number synchronization.")
      -- Check Sequence Number exceeding window
      C.memset(dec.window, 0, dec.window_size / 8) -- clear window
      enc.seq.no = 2^32
      dec.seq.no = 2^32 + dec.window_size + 1
      local px = op.encap(packet.clone(p))
      assert(not op.decap(px),
             "Accepted out of window Sequence Number.")
      assert(dec.seq:high() == 1 and dec.seq:low() == dec.window_size+1,
             "Corrupted Sequence Number.")
      -- Test anti-replay: From a set of 15 packets, first send all those
      -- that have an even sequence number.  Then, send all 15.  Verify that
      -- in the 2nd run, packets with even sequence numbers are rejected while
      -- the others are not.
      -- Then do the same thing again, but with offset sequence numbers so that
      -- we have a 32bit wraparound in the middle.
      local offset = 0 -- close to 2^32 in the 2nd iteration
      for offset = 0, 2^32-7, 2^32-7 do -- duh
         C.memset(dec.window, 0, dec.window_size / 8) -- clear window
         dec.seq.no = offset
         for i = 1+offset, 15+offset do
            if (i % 2 == 0) then
               enc.seq.no = i-1 -- so next seq will be i
               local px = op.encap(packet.clone(p))
               assert(op.decap(px),
                      "rejected legitimate packet seq=" .. i)
               assert(dec.seq.no == i,
                      "Lost sequence number synchronization")
            end
         end
         for i = 1+offset, 15+offset do
            enc.seq.no = i-1
            local px = op.encap(packet.clone(p))
            if (i % 2 == 0) then
               assert(not op.decap(px),
                      "accepted replayed packet seq=" .. i)
            else
               assert(op.decap(px),
                      "rejected legitimate packet seq=" .. i)
            end
         end
      end
      -- Check that packets from way in the past/way in the future (further
      -- than the biggest allowable window size) are rejected This is where we
      -- ultimately want resynchronization (wrt. future packets)
      C.memset(dec.window, 0, dec.window_size / 8) -- clear window
      dec.seq.no = 2^34 + 42
      enc.seq.no = 2^36 + 24
      local px = op.encap(packet.clone(p))
      assert(not op.decap(px),
             "accepted packet from way into the future")
      enc.seq.no = 2^32 + 42
      local px = op.encap(packet.clone(p))
      assert(not op.decap(px),
             "accepted packet from way into the past")
      -- Test resynchronization after having lost  >2^32 packets
      enc.seq.no = 0
      dec.seq.no = 0
      C.memset(dec.window, 0, dec.window_size / 8) -- clear window
      local px = op.encap(packet.clone(p)) -- do an initial packet
      assert(op.decap(px), "decapsulation failed")
      enc.seq:high(3) -- pretend there has been massive packet loss
      enc.seq:low(24)
      for i = 1, dec.resync_threshold do
         local px = op.encap(packet.clone(p))
         assert(not op.decap(px), "decapsulated pre-resync packet")
      end
      local px = op.encap(packet.clone(p))
      assert(op.decap(px), "failed to resynchronize")
      -- Make sure we don't accidentally resynchronize with very old replayed
      -- traffic
      enc.seq.no = 42
      for i = 1, dec.resync_threshold do
         local px = op.encap(packet.clone(p))
         assert(not op.decap(px), "decapsulated very old packet")
      end
      local px = op.encap(packet.clone(p))
      assert(not op.decap(px), "resynchronized with the past!")
   end
end
