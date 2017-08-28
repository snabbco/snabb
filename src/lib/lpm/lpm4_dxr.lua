module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local lpm4_trie = require("lib.lpm.lpm4_trie").LPM4_trie
local lpm4 = require("lib.lpm.lpm4")
local ip4 = require("lib.lpm.ip4")

LPM4_dxr = setmetatable({ alloc_storable = { "dxr_smints", "dxr_keys", "dxr_bottoms", "dxr_tops" } }, { __index = lpm4_trie })

ffi.cdef([[
uint16_t lpm4_dxr_search(uint32_t ip, uint16_t *ints, uint16_t *keys, uint32_t *bottoms, uint32_t *tops);
]])

function LPM4_dxr:new ()
   self = lpm4_trie.new(self)
   self:alloc("dxr_intervals", ffi.typeof("uint32_t"), 2000000)
   self:alloc("dxr_keys", ffi.typeof("uint16_t"), 2000000)
   self:alloc("dxr_smints", ffi.typeof("uint16_t"), 2000000)
   self:alloc("dxr_tops", ffi.typeof("uint32_t"), 2^16)
   self:alloc("dxr_bottoms", ffi.typeof("uint32_t"), 2^16)
   self.dxr_ioff = 0
   return self
end
function LPM4_dxr:print_intervals (first, last)
   local first = first or 0
   local last = last or self.dxr_ioff - 1
   for i = first, last do
      print(string.format("INTERVAL%d %s %s %d",
      i,
      ip4.tostring(self.dxr_intervals[i]),
      ip4.tostring(self.dxr_smints[i]),
      self.dxr_keys[i]
      ))
   end
   return self
end

function LPM4_dxr:build ()
   self.built = false
   self.dxr_ioff = 0
   self:build_intervals()
   self:build_compressed()
   self:build_direct()
   self.built = true
   return self
end
function LPM4_dxr:build_intervals ()
   local stk = ffi.new(ffi.typeof("$[33]", lpm4.entry))
   local soff = -1
   local previous = -1

   function bcast (e)
      return e.ip + 2^(32-e.length) - 1
   end
   function pop ()
      soff = soff - 1
   end
   function head ()
      return stk[soff]
   end
   function push (e)
      soff = soff + 1
      stk[soff].ip, stk[soff].length, stk[soff].key = e.ip, e.length, e.key
   end
   function empty ()
      return soff < 0
   end
   function add_interval (finish)
      previous = finish
      self.dxr_intervals[self.dxr_ioff] = finish
      self.dxr_keys[self.dxr_ioff] = head().key
      self.dxr_ioff = self.dxr_ioff + 1
   end

   for e in self:entries() do
      if e.ip == 0 and e.length == 0 then
         push(e)
      elseif bcast(head()) < e.ip then
         -- while there is something the stack that finishes before e.ip
         while(bcast(head()) < e.ip) do
            if bcast(head()) > previous then
               add_interval(bcast(head()))
            end
            pop()
         end
      end
      -- if there is a gap between the end of what we popped and this fill
      -- it with what's on the stack
      if previous + 1 < e.ip - 1 then
         add_interval(e.ip - 1)
      end
      push(e)
   end
   while not empty() do
      add_interval(bcast(head()))
      pop()
   end
   return self
end
function LPM4_dxr:build_compressed ()

   local ints = self.dxr_intervals
   local keys = self.dxr_keys
   local smints = self.dxr_smints

   local i,j = self.dxr_ioff, 0

   local function tbits(ip) return ffi.cast("uint32_t", bit.rshift(ip, 16)) end
   local function bbits(ip) return ffi.cast("uint16_t", bit.band(ip, 0xffff)) end
   for k = 0,i do
      if keys[k] == keys[k+1] and tbits(ints[k]) == tbits(ints[k+1]) then
      else
         keys[j] = keys[k]
         ints[j] = ints[k]
         smints[j] = bbits(ints[k])
         j = j + 1
      end
   end
   self.dxr_ioff = j
end
function LPM4_dxr:build_direct ()
   for i=0, 2^16 -1 do
      local base = i * 2^16
      self.dxr_bottoms[i] = self:search_interval(base)
      self.dxr_tops[i] = self:search_interval(base + 2^16-1)
   end
end

function LPM4_dxr:search_interval (ip)
   local ints = self.dxr_intervals
   local top = self.dxr_ioff - 1
   local bottom = 0
   local mid
   if self.built then
      local base = bit.rshift(ip, 16)
      top = self.dxr_tops[base]
      bottom = self.dxr_bottoms[base]
      ip = tonumber(ffi.cast("uint16_t", bit.band(ip, 0xffff)))
      ints = self.dxr_smints
   end

   while bottom < top do
      mid = math.floor( bottom + (top - bottom) / 2 )
      if ints[mid] < ip then
         bottom = mid + 1
      else
         top = mid
      end
   end
   return top
end

function LPM4_dxr:search (ip)
   return C.lpm4_dxr_search(ip, self.dxr_smints, self.dxr_keys, self.dxr_bottoms, self.dxr_tops)
   --return self.dxr_keys[self:search_interval(ip)]
end

function selftest ()
   local f = LPM4_dxr:new()
   f:add_string("0.0.0.0/0",700)
   f:add_string("128.0.0.0/8",701)
   f:add_string("192.0.0.0/8",702)
   f:add_string("192.0.0.0/16",703)
   f:add_string("224.0.0.0/8",704)
   f:build()
   function lsearch(f, ip)
      return f.dxr_keys[f:search_interval(ip4.parse(ip))]
   end
   assert(700 == lsearch(f, "1.1.1.1"))
   assert(701 == lsearch(f, "128.1.1.1"))
   assert(702 == lsearch(f, "192.1.1.1"))
   assert(703 == lsearch(f, "192.0.1.1"))
   assert(704 == lsearch(f, "224.1.1.1"))
   assert(700 == lsearch(f, "225.1.1.1"))

   assert(700 == f:search_string("1.1.1.1"))
   assert(701 == f:search_string("128.1.1.1"))
   assert(702 == f:search_string("192.1.1.1"))
   assert(703 == f:search_string("192.0.1.1"))
   assert(704 == f:search_string("224.1.1.1"))
   assert(700 == f:search_string("225.1.1.1"))
   LPM4_dxr:selftest()
end
