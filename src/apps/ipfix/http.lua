module(..., package.seeall)

local ffi      = require("ffi")
local lib      = require("core.lib")
local ctable   = require("lib.ctable")
local metadata = require("apps.rss.metadata")

-- Poor man's method to create a perfect hash table for a small number
-- of strings as keys. This is not guaranteed to work. In that case,
-- just use the best one we found (with the smallest maximum
-- displacement)
local function perfect_hash(strings)
   local min
   local i = 0
   -- Must match the size of httpRequestMethod
   local key_type_size = 8
   while i < 50 do
      local t = ctable.new({
            key_type = ffi.typeof("char[$]", key_type_size),
            value_type = ffi.typeof("uint8_t"), -- not used
            initial_size = #strings*2,
      })
      local entry = t.entry_type()
      for _, string in ipairs(strings) do
         assert(#string <= key_type_size)
         ffi.fill(entry, ffi.sizeof(entry))
         entry.key = string
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

-- RFC9110, section 9
local methods = {
   "GET",
   "HEAD",
   "POST",
   "PUT",
   "DELETE",
   "CONNECT",
   "OPTIONS",
   "TRACE",
}

-- Pre-allocated objects used in accumulate()
local methods_t = perfect_hash(methods)
local message, field = {}, {}

--- Utility functions to search for specific sequences of bytes in a
--- region of size length starting at ptr
local function init (str, ptr, length)
   str.start = ptr
   str.bytes = length
   str.pos = 0
end

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
      fn = function (entry, ptr, length)
         copy(ptr, length, entry.httpRequestHost)
      end
   }
}

local function decode_field (entry, ptr, length)
   init(field, ptr, length)
   local found, ptr, length = find_colon(field)
   if not found then return end
   for _, header in ipairs(headers) do
      if length == #header.name and ffi.C.strncasecmp(ptr, header.name, length) == 0 then
         strip_wspc(field)
         header.fn(entry, str(field))
      end
   end
end

function accumulate (self, entry, pkt)
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
   if not found then return end
   copy(ptr, length, entry.httpRequestMethod)
   if methods_t:lookup_ptr(entry.httpRequestMethod) == nil then
      self.counters.HTTP_invalid_method = self.counters.HTTP_invalid_method + 1
      ffi.fill(entry.httpRequestMethod, ffi.sizeof(entry.httpRequestMethod))
      return
   end
   found, ptr, length = find_spc(message)
   if not found then return end
   copy(ptr, length, entry.httpRequestTarget)
   -- Skip HTTP version
   found, _, _ = find_crlf(message)
   if not found then return end
   while true do
      found, ptr, length = find_crlf(message)
      -- The sequence of fields is terminated by a an empty line
      if not found or length == 0 then break end
      decode_field(entry, ptr, length)
   end
end
