module(..., package.seeall)

local ffi      = require("ffi")
local lib      = require("core.lib")
local ctable   = require("lib.ctable")
local metadata = require("apps.rss.metadata")

-- Poor man's method to create a perfect hash table for a small number
-- of keys. This is not guaranteed to work. In that case, just use the
-- best one we found (with the smallest maximum displacement).  The
-- keys are assumed to be strings.
local function perfect_hash(table)
   local min, best
   local i, key_type_size = 0, 0
   for key, _ in pairs(table) do
      if #key > key_type_size then
         key_type_size = #key
      end
   end
   while i < 50 do
      local t = ctable.new({
            key_type = ffi.typeof("char[$]", key_type_size),
            -- Used for Flowmon
            value_type = ffi.typeof("uint16_t"),
            initial_size = #table*2,
      })
      local entry = t.entry_type()
      for key, value in pairs(table) do
         ffi.fill(entry, ffi.sizeof(entry))
         entry.key = key
         entry.value = value
         t:add(entry.key, entry.value)
      end
      if t.max_displacement == 0 then return t end
      if min == nil or t.max_displacement < min then
         min = t.max_displacement
         best = t
      end
      i = i + 1
   end
   return best
end

-- RFC9110, section 9. The values in this table are only used for the
-- HTTP_Flowmon template, which stores the request method as a bitmask
-- rather than as a string like the standard IPFIX element.
local methods = {
   ["GET"]     = 0x0001,
   ["POST"]    = 0x0002,
   ["HEAD"]    = 0x0004,
   ["PUT"]     = 0x0008,
   ["OPTIONS"] = 0x0010,
   ["DELETE"]  = 0x0020,
   ["TRACE"]   = 0x0040,
   ["CONNECT"] = 0x0100,
   -- Not implemented
   ["PATCH"]   = 0x0080,
   ["SSL"]     = 0x0200,
}

-- Pre-allocated objects used in accumulate()
local methods_t = perfect_hash(methods)
local methods_t_entry = methods_t.entry_type()
local methods_t_key_size = ffi.sizeof(methods_t_entry.key)
local message, field = {}, {}

--- Utility functions to search for specific sequences of bytes in a
--- region of size length starting at ptr
local function init (str, ptr, length)
   str.start = ptr
   str.bytes = length
   str.pos = 0
end

-- Return pointer and length of the string at the current position
local function str (str)
   return str.start + str.pos, str.bytes - str.pos
end

-- Scan the buffer from the current location until the match condition
-- is met. Returns a pointer to the start position and a length that
-- does not include the matching pattern. Advances the current
-- position to the first byte following the matching pattern.
local function mk_search_fn (ctype, match_fn)
   local ptr_t = ffi.typeof("$*", ctype)
   return function (str)
      local pos = str.pos
      local start = str.start
      local ptr = start + pos
      local found = false
      while (pos < str.bytes and not found) do
         found = match_fn(ffi.cast(ptr_t, start + pos))
         pos = pos + 1
      end
      local length = pos - str.pos - 1
      str.pos = pos - 1 + ffi.sizeof(ctype)
      return found, ptr, length
   end
end

local function find_bytes (type, bytes)
   return mk_search_fn(
      ffi.typeof(type),
      function (str)
         return str[0] == bytes
      end
   )
end

local find_spc = find_bytes("uint8_t", 0x20)
local find_colon = find_bytes("uint8_t", 0x3a)
local find_crlf = find_bytes("uint16_t", 0x0a0d) -- correct for endianness
local wspc = {
   [0x20] = true,
   [0x09] = true,
   [0x0d] = true,
   [0x0a] = true
}
-- Strip leading and trailing white space from str
local function strip_wspc (str)
   local pos = str.pos
   while wspc[str.start[pos]] and pos < str.bytes do
      pos = pos + 1
   end
   str.pos = pos
   pos = str.bytes
   while wspc[str.start[pos-1]] and pos > str.pos do
      pos = pos - 1
   end
   str.bytes = pos
end

local function copy (ptr, length, obj)
   local obj_len = ffi.sizeof(obj)
   local eff_length =  math.min(length, obj_len)
   ffi.fill(obj, obj_len)
   ffi.copy(obj, ptr, eff_length)
end

local headers = {
   {
      name = "host",
      fn = function (entry, ptr, length, flowmon)
         if flowmon then
            copy(ptr, length, entry.fmHttpRequestHost)
         else
            copy(ptr, length, entry.httpRequestHost)
         end
      end
   }
}

local function decode_field (entry, ptr, length, flowmon)
   init(field, ptr, length)
   local found, ptr, length = find_colon(field)
   if not found then return end
   for _, header in ipairs(headers) do
      if length == #header.name and ffi.C.strncasecmp(ptr, header.name, length) == 0 then
         strip_wspc(field)
         local ptr, length = str(field)
         header.fn(entry, ptr, length, flowmon)
      end
   end
end

function accumulate (self, entry, pkt, flowmon)
   local md = metadata.get(pkt)
   local tcp_header_size = 4 * bit.rshift(ffi.cast("uint8_t*", md.l4)[12], 4)
   local payload = md.l4 + tcp_header_size
   local size = pkt.data + pkt.length - payload
   if (md.length_delta > 0) then
      -- Remove padding
      size = size - md.length_delta
   end
   if (size == 0) then
      return
   end
   -- Only process the first packet with non-zero payload after the
   -- TCP handshake is completed.
   entry.state.done = 1
   self.counters.HTTP_flows_examined = self.counters.HTTP_flows_examined + 1
   init(message, payload, size)
   local found, ptr, length = find_spc(message)
   if not found or length > methods_t_key_size then return end
   copy(ptr, length, methods_t_entry.key)
   local method = methods_t:lookup_ptr(methods_t_entry.key)
   if method == nil then
      self.counters.HTTP_invalid_method = self.counters.HTTP_invalid_method + 1
      return
   end
   if flowmon then
      entry.fmHttpRequestMethod = method.value
   else
      copy(ptr, length, entry.httpRequestMethod)
   end
   found, ptr, length = find_spc(message)
   if not found then return end
   if flowmon then
      copy(ptr, length, entry.fmHttpRequestTarget)
   else
      copy(ptr, length, entry.httpRequestTarget)
   end
   -- Skip HTTP version
   found, _, _ = find_crlf(message)
   if not found then return end
   while true do
      found, ptr, length = find_crlf(message)
      -- The sequence of fields is terminated by a an empty line
      if not found or length == 0 then break end
      decode_field(entry, ptr, length, flowmon)
   end
end
