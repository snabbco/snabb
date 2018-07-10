module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C

local lpm4_trie = require("lib.lpm.lpm4_trie").LPM4_trie
local bit = require("bit")

ffi.cdef([[
uint16_t lpm4_248_search(uint32_t ip, int16_t *big, int16_t *little);
uint32_t lpm4_248_search32(uint32_t ip, int32_t *big, int32_t *little);
]])

LPM4_248 = setmetatable({ alloc_storable = { "lpm4_248_bigarry", "lpm4_248_lilarry" } }, { __index = lpm4_trie })

function LPM4_248:search16 (ip)
   return C.lpm4_248_search(ip, self.lpm4_248_bigarry, self.lpm4_248_lilarry)
end
function LPM4_248:search32 (ip)
   return C.lpm4_248_search32(ip, self.lpm4_248_bigarry, self.lpm4_248_lilarry)
end

function LPM4_248:new (cfg)
   -- call the superclass constructor while allowing lpm4_248 to be subclassed
   self = lpm4_trie.new(self)
   local cfg = cfg or {}
   self.keybits = cfg.keybits or 15

   local arrytype
   if self.keybits == 15 then
      arrytype = "uint16_t"
      self.search = LPM4_248.search16
   elseif self.keybits == 31 then
      arrytype = "uint32_t"
      self.search = LPM4_248.search32
   else
      error("LPM4_248 supports 15 or 31 keybits")
   end
   self:alloc("lpm4_248_bigarry", ffi.typeof(arrytype), 2^24)
   self:alloc("lpm4_248_lilarry", ffi.typeof(arrytype), 1024*256)
   self.flag = ffi.new(arrytype, 2^self.keybits)
   self.mask = self.flag - 1
   return self
end

function LPM4_248:build ()
   local taboff = 1

   local function add(ip, len, key)
      local base = bit.rshift(ip, 8)
      if len < 25 then
         local count = 2^(24-len)
         for i = 0, count - 1 do
            self.lpm4_248_bigarry[base + i] = key
         end
      end
      if len > 24 then
         local e = self.lpm4_248_bigarry[base]
         local bottom = bit.band(ip, 0xff)
         if bit.band(self.flag, e) ~= self.flag then
            if e ~= 0 then
               for i = 0,255 do
                  self.lpm4_248_lilarry[256*taboff + i] = e
               end
            end
            self.lpm4_248_bigarry[base] = taboff + self.flag
            taboff = taboff + 1
            -- each tab is '8bits' of ip long, so multiply by 256, 512 is double 256
            if 256 * taboff == self:lpm4_248_lilarry_length() then
               self:lpm4_248_lilarry_grow()
            end
         end
         local tab = self.lpm4_248_lilarry + 256*bit.band(self.lpm4_248_bigarry[base], self.mask)
         for i = tonumber(bottom), tonumber(bottom) + 2^(32-len) - 1 do
            tab[i] = key
         end
      end
   end
   for e in self:entries() do
      add(e.ip, e.length, e.key)
   end
   print("Build 24_8 with " .. taboff-1 .. " tables")
   return self
end

function selftest ()
   print("LPM4_248 15bit keys")
   LPM4_248:selftest()
   print("LPM4_248 31bit keys")
   LPM4_248:selftest({ keybits = 31 })
end
