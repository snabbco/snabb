module(..., package.seeall)

local ffi = require("ffi")

ct_t = ffi.typeof([[
   struct {
      uint8_t *text;
      uint16_t length;
      uint16_t pos;
   }
]])

function ct_set(ct, pos)
   ct.pos = pos
end

function ct_get(ct)
   return ct.pos
end

function ct_at(ct)
   return ct.text + ct.pos
end

function ct_init(ct, text, length, pos)
   ct.text = text
   ct.length = length
   ct.pos = pos or 0
end

function search(string, ct, tail)
   local slen = string.len
   local pos = ct.pos
   while (pos + slen < ct.length) do
      if ffi.C.strncasecmp(string.buf, ct.text + pos, slen) == 0 then
         if tail then pos = pos + slen end
         ct.pos = pos
         return pos
      end
      pos = pos + 1
   end
   return nil
end

function upto_space_or_cr(ct)
   local text = ct.text
   local pos = ct.pos
   local pos_start = pos
   while (pos < ct.length and text[pos] ~= 32 and text[pos] ~= 13) do
      pos = pos + 1
   end
   ct.pos = pos
   return pos, pos - pos_start
end

function skip_space(ct)
   local text = ct.text
   local pos = ct.pos
   local pos_start = pos
   while (pos < ct.length and text[pos] == 32) do
      pos = pos + 1
   end
   ct.pos = pos
   return pos, pos - pos_start
end

function string_to_buf(s)
   -- Using ffi.new("uint8_t[?]", #s) results in trace aborts due to
   -- "bad argument type" in ffi.sizeof()
   local buf = ffi.new("uint8_t["..#s.."]")
   for i = 1, #s do
      buf[i-1] = s:byte(i,i)
   end
   return buf
end

function strings_to_buf(t)
   local result = {}
   for k, v in pairs(t) do
      result[k] = {
         buf = string_to_buf(v),
         len = #v
      }
   end
   return result
end
