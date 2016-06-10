module(..., package.seeall)
local ffi = require("ffi")
local header = require("lib.protocol.header")

local esp_tail = subClass(header)

-- Class variables
esp_tail._name = "esp_tail"
esp_tail:init(
   {
      [1] = ffi.typeof[[
            struct {
               uint8_t pad_length;
               uint8_t next_header;
            } __attribute__((packed))
      ]]
   })

-- Class methods

function esp_tail:new (config)
   local o = esp_tail:superClass().new(self)
   o:pad_length(config.pad_length)
   o:next_header(config.next_header)
   return o
end

-- Instance methods

function esp_tail:pad_length (length)
   local h = self:header()
   if length ~= nil then
      h.pad_length = length
   else
      return h.pad_length
   end
end

function esp_tail:next_header (next_header)
   local h = self:header()
   if next_header ~= nil then
      h.next_header = next_header
   else
      return h.next_header
   end
end

return esp_tail
