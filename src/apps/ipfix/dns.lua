module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")

-- By default, CNAME and RRSIG records in the answer section are
-- skipped.
skip_CNAMEs_RRSIGs = true

local uint16_ptr_t = ffi.typeof("uint16_t *")
local uint8_ptr_t = ffi.typeof("uint8_t *")

local dns_hdr_t = ffi.typeof([[
   struct {
      uint16_t id;
      uint16_t flags;
      uint16_t qcount;
      uint16_t anscount;
      uint16_t authcount;
      uint16_t addcount;
   } __attribute__((packed))
]])
local dns_hdr_ptr_t = ffi.typeof("$*", dns_hdr_t)

-- The part of a RR following the encoded name
local rr_t = ffi.typeof([[
  struct {
     uint16_t type;
     uint16_t class;
     uint32_t ttl;
     uint16_t rdlength;
     uint8_t rdata[0];
  } __attribute__((packed))
]])
local rr_ptr_t = ffi.typeof("$*", rr_t)

-- Given a region of memory of size size starting at start_ptr, return
-- the number of bytes in the sub-region starting at data_ptr.  A
-- result <= 0 indicates that data_ptr is not within the region.
local function available_bytes(start_ptr, size, data_ptr)
   assert(data_ptr >= start_ptr)
   return size - (data_ptr - start_ptr)
end

-- Incorrectly compressed domain names can form loops.  We use a table
-- that can hold all possible offsets (14 bits) encoded in compressed
-- names to detect such loops in a branch-free fashion by marking
-- which offsets have been encountered while de-compressing a
-- name. The marker consist of a 16-bit number which is increased for
-- each invocation of decompress_name().  The offset table must be
-- reset each time the marker wraps around to zero.  Because a valid
-- offset must be at least 12 (due it being relative to the start of
-- the DNS header), the current marker is stored in offset_table[0]
-- without causing a conflict.
local offset_table = ffi.new("uint16_t [16384]")

-- Decompress the on-the-wire representation of a domain name starting
-- at ptr and write up to size bytes of the decompressed name to the
-- location pointed to by buffer. hdr_ptr is a pointer to the
-- beginning of the DNS header to resolve compressed names.
--
-- Note that DNS extraction is only initiated if the packet is not
-- truncated. Even then, decompression can lead us out of the message
-- if
--
--   * the message is corrupt
--   * the messages is fragmented and decompression points into
--     a non-initial fragment
--
-- msg_size is the number of bytes in the message, including the
-- header, used to check whether decompression stays within the
-- message.
--
-- Returns a pointer to the first byte after the name or nil if the
-- name could not be decompressed and the number of bytes that have
-- been copied to the buffer.  If the pointer is nil, the buffer
-- contains what has been decompressed so far.
local function decompress_name(hdr_ptr, msg_size, ptr, buffer, size)
   offset_table[0] = offset_table[0] + 1
   if offset_table[0] == 0 then
      ffi.fill(offset_table, ffi.sizeof(offset_table))
      offset_table[0] = 1
   end

   local offset = 0
   if available_bytes(hdr_ptr, msg_size, ptr) < 1 then
      return nil, offset
   end
   local result_ptr = nil
   local length = ptr[0]
   while length ~= 0 do
      local label_type = bit.band(0xc0, length)
      if label_type == 0xc0 then
         if available_bytes(hdr_ptr, msg_size, ptr) < 2 then
            return nil, offset
         end
         -- Compressed name, length is the offset relative to the start
         -- of the DNS message where the remainder of the name is stored
         local name_offset =
            bit.band(0x3fff, lib.ntohs(ffi.cast(uint16_ptr_t, ptr)[0]))
         -- Sanity check and Loop detection
         if (name_offset < ffi.sizeof(dns_hdr_t) or name_offset >= msg_size or
             offset_table[name_offset] == offset_table[0]) then
            return nil, offset
         end
         offset_table[name_offset] = offset_table[0]
         if result_ptr == nil then
            -- This is the first redirection encountered in the name,
            -- the final result is the location just behind that
            -- pointer
            result_ptr = ptr + 2
         end
         ptr = hdr_ptr + name_offset
      elseif label_type ~= 0 then
         -- Unsupported/undefined label type
         return nil, offset
      else
         if available_bytes(hdr_ptr, msg_size, ptr) < length + 1 then
            -- Truncated label
            return nil, offset
         end
         -- Remaining space in the buffer for the name
         local avail = size - offset
         if avail > 0 then
            -- Copy as much of the label as possible
            local eff_length = math.min(length+1, avail)
            ffi.copy(buffer + offset, ptr, eff_length)
            offset = offset + eff_length
         end
         ptr = ptr + length + 1
      end
      length = ptr[0]
   end
   -- We've reached the root label
   if offset < size then
      buffer[offset] = 0
      offset = offset + 1
   end
   if result_ptr == nil then
      result_ptr = ptr + 1
   end
   return result_ptr, offset
end

-- RDATA with a single domain name
local function decompress_RR_plain(hdr_ptr, msg_size, rr, entry)
   local ptr, rdlength = decompress_name(hdr_ptr, msg_size, rr.rdata,
                                         entry.key.dnsAnswerRdata,
                                         ffi.sizeof(entry.key.dnsAnswerRdata))
   entry.key.dnsAnswerRdataLen = rdlength
   return ptr
end

local mx_rdata_t = ffi.typeof([[
   struct {
      uint16_t preference;
      uint8_t  exchange[0];
   }
]])
local mx_rdata_ptr_t = ffi.typeof("$*", mx_rdata_t)
local function decompress_RR_MX(hdr_ptr, msg_size, rr, entry)
   local mx_src = ffi.cast(mx_rdata_ptr_t, rr.rdata)
   local mx_dst = ffi.cast(mx_rdata_ptr_t, entry.key.dnsAnswerRdata)
   mx_dst.preference = mx_src.preference
   local ptr, length =
      decompress_name(hdr_ptr, msg_size, mx_src.exchange,
                      mx_dst.exchange, 
                      ffi.sizeof(entry.key.dnsAnswerRdata) - 2)
   local rdlength = length + 2
   entry.key.dnsAnswerRdataLen = rdlength
   return ptr
end

local soa_rdata_t = ffi.typeof([[
   struct {
      uint32_t serial;
      uint32_t refresh;
      uint32_t retry;
      uint32_t expire;
      uint32_t minimum;
   }
]])
local function decompress_RR_SOA(hdr_ptr, msg_size, rr, entry)
   local size = ffi.sizeof(entry.key.dnsAnswerRdata)
   local dst = entry.key.dnsAnswerRdata
   -- MNAME
   local ptr, length =
      decompress_name(hdr_ptr, msg_size, rr.rdata, dst, size)
   if ptr ~= nil then
      local rdlength = ffi.sizeof(soa_rdata_t) + length
      local avail = size - length
      dst = dst + length
      -- RNAME
      ptr, length = decompress_name(hdr_ptr, msg_size, ptr, dst, avail)
      if ptr ~= nil then
         rdlength = rdlength + length
         avail = avail - length
         dst = dst + length
         if avail > 0 then
            ffi.copy(dst, ptr, math.min(avail, ffi.sizeof(soa_rdata_t)))
         end
         entry.key.dnsAnswerRdataLen = rdlength
      end
   end
   return ptr
end

local function decompress_rdata_none(hdr_ptr, msg_size, rr, entry)
   local rdlength = lib.ntohs(rr.rdlength)
   ffi.copy(entry.key.dnsAnswerRdata, rr.rdata,
            math.min(rdlength, ffi.sizeof(entry.key.dnsAnswerRdata)))
   entry.key.dnsAnswerRdataLen = rdlength
   return true
end

-- List of well-known RR types (see RFC3597, section 4) whose RDATA
-- sections can contain compressed names.  The functions referenced
-- here replace such names with their uncompressed equivalent.
local decompress_rdata_fns = setmetatable(
   {
      [2]  = decompress_RR_plain, -- NS
      [5]  = decompress_RR_plain, -- CNAME
      [6]  = decompress_RR_SOA,   -- SOA
      [12] = decompress_RR_plain, -- PTR
      [15] = decompress_RR_MX,    -- MX
   },
   { __index =
        function()
           return decompress_rdata_none
        end
   }
)
local function extract_answer_rr(hdr_ptr, msg_size, ptr, entry)
   local ptr, len = decompress_name(hdr_ptr, msg_size, ptr,
                                    entry.key.dnsAnswerName,
                                    ffi.sizeof(entry.key.dnsAnswerName))
   if ptr == nil then
      return nil, nil, nil
   end
   if available_bytes(hdr_ptr, msg_size, ptr) < ffi.sizeof(rr_t) then
      return nil, nil, nil
   end
   local rr = ffi.cast(rr_ptr_t, ptr)
   local type = lib.ntohs(rr.type)
   local rdlength = lib.ntohs(rr.rdlength)
   if rdlength > 0 then
      if available_bytes(hdr_ptr, msg_size, rr.rdata) < rdlength then
         return nil, nil, nil
      end
      if not decompress_rdata_fns[type](hdr_ptr, msg_size, rr, entry) then
         return nil, nil, nil
      end
   end
   local class = lib.ntohs(rr.class)
   entry.key.dnsAnswerType = type
   entry.key.dnsAnswerClass = class
   entry.key.dnsAnswerTtl = lib.ntohl(rr.ttl)
   return type, class, rr.rdata + rdlength
end

function extract(hdr_ptr, msg_size, entry)
   if ffi.sizeof(dns_hdr_t) > msg_size then
      return
   end
   local dns_hdr = ffi.cast(dns_hdr_ptr_t, hdr_ptr)
   entry.key.dnsFlagsCodes = lib.ntohs(dns_hdr.flags)
   if lib.ntohs(dns_hdr.qcount) == 1 then
      entry.key.dnsQuestionCount = 1
      local ptr, _ = decompress_name(hdr_ptr, msg_size,
                                     hdr_ptr + ffi.sizeof(dns_hdr_t),
                                     entry.key.dnsQuestionName,
                                     ffi.sizeof(entry.key.dnsQuestionName))
      if ptr == nil then
         ffi.fill(entry.key.dnsQuestionName,
                  ffi.sizeof(entry.key.dnsQuestionName))
         return
      end
      -- The question section only has a type and class
      if available_bytes(hdr_ptr, msg_size, ptr) < 4 then
         return
      end
      local rr = ffi.cast(rr_ptr_t, ptr)
      entry.key.dnsQuestionType = lib.ntohs(rr.type)
      entry.key.dnsQuestionClass = lib.ntohs(rr.class)
      ptr = ptr + 4
      local anscount = lib.ntohs(dns_hdr.anscount)
      entry.key.dnsAnswerCount = anscount
      if anscount > 0 then
         -- Extract the first answer
         local type, class, ptr =
            extract_answer_rr(hdr_ptr, msg_size, ptr, entry)

         -- Skip to the first RR which is neither a CNAME nor a RRSIG
         if skip_CNAMEs_RRSIGs then
            anscount = anscount - 1
            while (type == 5 or type == 46) and class == 1 and anscount > 0 do
               ffi.fill(entry.key.dnsAnswerName,
                        ffi.sizeof(entry.key.dnsAnswerName))
               ffi.fill(entry.key.dnsAnswerRdata,
                        ffi.sizeof(entry.key.dnsAnswerRdata))
               type, class, ptr = extract_answer_rr(hdr_ptr, msg_size, ptr, entry)
               anscount = anscount - 1
            end
         end
      end
   end
end
