module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local bit = require("bit")
local lpm4_trie = require("lib.lpm.lpm4_trie").LPM4_trie
local bor, band, lshift, rshift, bnot = bit.bor, bit.band, bit.lshift, bit.rshift, bit.bnot
local tohex = bit.tohex
local ip4 = require("lib.lpm.ip4")
local masked = ip4.masked

LPM4_poptrie = setmetatable({}, { __index = lpm4_trie })

local node = ffi.typeof([[
struct {
   int32_t jumpn;
   int32_t jumpl;
   uint64_t maskn;
   uint64_t maskl;
}
]])
function get_bits (ip, offset)
   assert(offset >= 0 and offset < 27)
   return band(rshift(ip, 26-offset), 0x3f)
end
function mask_set_bit (mask, offset)
   return bor(mask, lshift(1ull, 63 - offset))
end
function mask_clear_bit (mask, offset)
   return band(mask, bnot(lshift(1ull, 63 - offset)))
end
function mask_get_bit (mask, offset)
   return band(1, rshift(mask, 63 - offset))
end
function mask_popcnt (mask)
   local c = 0
   for i = 0,63 do
      if mask_get_bit(mask, i) == 1 then
         c = c + 1
      end
   end
   return c
end

function LPM4_poptrie:new ()
   self = lpm4_trie.new(self)
   return self
end
function LPM4_poptrie:print_nodes ()
   local n = self.poptrie_nodes
   local i = 0
   repeat
      print("node", i, "jumpn", n[i].jumpn)
      print("node", i, "maskn", tohex(n[i].maskn))
      print("node", i, "jumpl", n[i].jumpl)
      print("node", i, "maskl", tohex(n[i].maskl))
      i = i + 1
   until n[i].jumpl == 0 and n[i].maskl == 0 and n[i].maskn and n[i].jumpn == 0
end
function LPM4_poptrie:build ()
   self:alloc("poptrie_nodes", ffi.typeof(node), 1000)
   self:alloc("poptrie_leaves", ffi.typeof("uint16_t"), 1000)

   local nodes = self.poptrie_nodes
   local leaves = self.poptrie_leaves
   local ts = self.trie
   local nextleaf = 0
   local nextnode = 1

   local function add(ip, len, key)
      local p = 0
      local offset = 0
      local ts = self.lpm4_trie
      while true do
         local e = nodes[p]
         if e.jumpl == 0 and e.maskl == 0 and e.maskn == 0 and e.jumpn == 0 then
            -- then nothing has been initialised :(
            e.jumpl = nextleaf
            e.jumpn = nextnode
            local lastleaf
            local base = masked(ip, offset)
            for i=0,63 do
               local slotip = bit.bor(base, lshift(i, 32 - (offset + 6)))
               if self:has_child(slotip, offset + 6) then
                  e.maskn = mask_set_bit(e.maskn, get_bits(slotip, offset), 1)
                  nextnode = nextnode + 1
               else
                  -- This prefix is a leaf
                  local t = self:search_trie(slotip, offset + 6)
                  local key = 0
                  if t then key = ts[t].key end
                  if lastleaf ~= key then
                     local bits = get_bits(slotip, offset)
                     e.maskl = mask_set_bit(e.maskl, bits, 1)
                     leaves[nextleaf] = key

                     nextleaf = nextleaf + 1
                     lastleaf = key
                  end
               end
            end
         end
         local bits = get_bits(ip, offset)
         if mask_get_bit(nodes[p].maskn, bits) == 0 then return end

         p = nodes[p].jumpn + mask_popcnt(bit.band(lshift(bit.bnot(0LL), 63 - bits), nodes[p].maskn)) - 1
         offset = offset + 6
      end
   end
   for e in self:entries() do
      self:print_entry(e)
      add(e.ip, e.length, e.key)
   end
   return self
end
function LPM4_poptrie:search (ip)
   local offset = 0
   local nodes = self.poptrie_nodes
   local leaves = self.poptrie_leaves
   local i = 0

   while true do
      local bits = get_bits(ip, offset)
      if mask_get_bit(nodes[i].maskn, bits) == 1 then
         -- a node keep going
         i = nodes[i].jumpn - 1 + mask_popcnt(bit.band(lshift(bit.bnot(0LL), 63 - bits), nodes[i].maskn))
         offset = offset + 6
      else
         return leaves[nodes[i].jumpl - 1 + mask_popcnt(bit.band(lshift(bit.bnot(0LL), 63 - bits), nodes[i].maskl, bit.bnot(nodes[i].maskn)))]
      end
   end
end

function selftest_masks ()
   print("selftest_masks()")
   local msb = mask_set_bit
   local mgb = mask_get_bit
   local mcb = mask_clear_bit
   local popcnt = mask_popcnt
   assert(mgb(0, 63)  == 0)
   assert(mgb(1, 63)  == 1)
   assert(mgb(2, 62)  == 1)
   assert(mgb(3, 62)  == 1)
   assert(msb(0, 0)   == 0x8000000000000000ull)
   assert(msb(0, 1)   == 0x4000000000000000ull)
   assert(msb(1, 62)  == 0x0000000000000003ull)
   assert(msb(1, 31)  == 0x0000000100000001ull)
   assert(msb(1, 30)  == 0x0000000200000001ull)
   assert(msb(1, 0)   == 0x8000000000000001ull)
   assert(mcb(1, 63) == 0)
   assert(mcb(msb(0,0), 0) == 0)
   assert(popcnt(3ull) == 2)
   assert(popcnt(msb(255, 0)) == 9)
end
function selftest_get_bits ()
   print("selftest_get_bits()")
   local p = ip4.parse
   local g = get_bits
   assert(g(p("63.0.0.0"),2) == 63)
   assert(g(p("0.63.0.0"),10) == 63)
   assert(g(p("0.0.63.0"),18) == 63)
   assert(g(p("0.0.0.63"),26) == 63)
   assert(g(p("0.3.0.0"),14) == 48)
   assert(g(p("0.3.128.0"),14) == 56)
   assert(g(p("192.0.0.0"),0) == 48)
   local pmu = require("lib.pmu")
   local avail, err = pmu.is_available()
   if not avail then
      print("PMU not available:")
      print("  "..err)
      print("Skipping benchmark.")
   else
      local n = 0
      pmu.profile(function()
         for i =0, 1000*1000*1000 do n = n + g(i, 7) end
      end)
   end
end
function selftest ()
   local n = LPM4_poptrie:new()
   n:add_string("128.0.0.0/1", 2)
   n:add_string("192.0.0.0/2", 3)
   n:add_string("224.0.0.0/3", 4)
   n:add_string("240.0.0.0/4", 5)
   n:add_string("240.128.0.0/10", 6)
   n:build()
   assert(n:search_string("128.0.0.0") == 2)
   assert(n:search_string("192.0.0.0") == 3)
   assert(n:search_string("224.0.0.0") == 4)
   assert(n:search_string("240.0.0.0") == 5)
   assert(n:search_string("241.0.0.0") == 5)
   assert(n:search_string("242.0.0.0") == 5)
   assert(n:search_string("243.0.0.0") == 5)
   assert(n:search_string("244.0.0.0") == 5)
   assert(n:search_string("240.128.0.0") == 6)
   assert(n:search_string("240.129.0.0") == 6)
   assert(n:search_string("240.192.0.0") == 5)

   selftest_get_bits()
   selftest_masks()
end
