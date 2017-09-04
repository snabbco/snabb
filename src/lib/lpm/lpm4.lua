module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local rand = require("lib.lpm.random").u32
local bit = require("bit")
local lib = require("core.lib")
local lpm = require("lib.lpm.lpm").LPM
local ip4 = require("lib.lpm.ip4")

LPM4 = setmetatable({}, { __index = lpm })

entry = ffi.typeof([[
struct {
   uint32_t ip;
   int32_t key;
   int32_t length;
}
]])
local verify_ip_count = 2000000

function LPM4:print_entry (e)
   print(string.format("%s/%d %d", ip4.tostring(e.ip), e.length, e.key))
end
function LPM4:print_entries ()
   for e in self:entries() do
      self:print_entry(e)
   end
end
function LPM4:search_bytes (bytes)
   local ip = ffi.cast("uint32_t*", bytes)[0]
   return self:search(lib.ntohl(ip))
end
function LPM4:search_entry (ip)
   error("Must be implemented in a subclass")
end
function LPM4:search_entry_exact (ip, len)
   error("Must be implemented in a subclass")
end
function LPM4:search_entry_string (ip)
   return self:search_entry(ip4.parse(ip))
end
function LPM4:search (ip)
   return self:search_entry(ip).key
end
function LPM4:search_string (str)
   return self:search(ip4.parse(str))
end
function LPM4:search_cidr (cidr)
   return self:search_entry_exact(ip4.parse_cidr(cidr))
end
function LPM4:add (ip, len, key)
   error("Must be implemented in a subclass")
end
function LPM4:add_string (cidr, key)
   local net, len = ip4.parse_cidr(cidr)
   self:add(net, len, key)
end
function LPM4:add_from_file (pfxfile)
   for line in io.lines(pfxfile) do
      local cidr, key = string.match(line, "(%g*)%s*(%g*)")
      self:add_string(cidr, tonumber(key))
   end
   return self
end
function LPM4:remove (ip, len)
   error("Must be implemented in a subclass")
end
function LPM4:remove_string (cidr)
   local net, len = ip4.parse_cidr(cidr)
   self:remove(net, len)
end
function LPM4:build ()
   return self
end

function LPM4:benchmark (million)
   local million = million or 100000000
   local pmu = require("lib.pmu")
   local ip

   self:build()

   local funcs = {
      ["data dependency"] = function()
         for i = 1, million do ip = rand(ip) + self:search(ip) end
      end,
      ["no lookup"] = function()
         for i = 1, million do ip = rand(ip) + 1 end
      end,
      ["no dependency"] = function()
         for i = 1, million do
            ip = rand(ip) + 1
            self:search(ip)
         end
      end
   }
   for n,f in pairs(funcs) do
      print(n)
      ip = rand(314159)
      pmu.profile(
      f,
      {
         "mem_load_uops_retired.llc_hit",
         "mem_load_uops_retired.llc_miss",
         "mem_load_uops_retired.l2_miss",
         "mem_load_uops_retired.l2_hit"
      },
      { lookup = million }
      )
      print()
   end
end

function LPM4:verify (trusted)
   local ip = rand(271828)
   for i = 0,verify_ip_count do
      local ipstr = ip4.tostring(ip)
      local expected = trusted:search(ip)
      local key = self:search(ip)
      assert(expected == key, string.format("%s got %d expected %d", ipstr, key, expected))
      ip = rand(ip)
   end
end

function LPM4:verify_against_fixtures (pfxfile, verifyfile)
   self:add_from_file(pfxfile)
   self:build()
   local count = 0
   for line in io.lines(verifyfile) do
      local ip, tcidr, key = string.match(line, "(%g*) (%g*) (%g*)")
      local found = self:search_entry_string(ip)
      assert(found.key == tonumber(key),
      string.format("Search %d for %s found (%s/%d) %s expected (%s) %d ", count, ip, ip4.tostring(found.ip), found.length, found.key, tcidr, key))
      count = count + 1
   end
end
function LPM4:build_verify_fixtures (pfxfile, ipfile)
   local f = LPM4:new()
   local out = assert(io.open(pfxfile, "w",
   "unable to open " .. pfxfile .. " for writing"))
   f.add = function (self,ip,len,key)
      out:write(string.format("%s/%d %d\n", ip4.tostring(ip), len, key))
   end
   f:add_random_entries()

   local out = assert(io.open(ipfile, "w",
   "unable to open " .. pfxfile .. " for writing"))
   local ip = rand(271828)
   for i = 0, verify_ip_count do
      out:write(ip4.tostring(ip) .. "\n")
      ip = rand(ip)
   end
end
function LPM4:remove_random_entries ()
   local count = self.entry_count - 1
   local ents = self.lpm4_ents
   local removen = math.floor(count * 0.1)
   -- Set a random seed so that remove_random_entries
   -- removes the same entries if run across different objects
   math.randomseed(9847261856)
   for i = 1,removen do
      local remove = math.random(1, count)
      ents[remove].ip, ents[count].ip = ents[count].ip, ents[remove].ip
      ents[remove].length, ents[count].length = ents[count].length, ents[remove].length
      ents[remove].key, ents[count].key = ents[count].key, ents[remove].key
      self:remove(ents[count].ip, ents[count].length)
      count = count - 1
   end
   self.entry_count = count
end
function LPM4:verify_entries_method ()
   local against = {}
   print("Verifying " .. tostring(self.entry_count) .. " entries")
   for e in self:entries() do
      local cidr = ip4.tostring(e.ip) .. "/" .. e.length
      against[cidr] = e.key
   end
   for i = 0, self.entry_count - 1 do
      local cidr = ip4.tostring(self.lpm4_ents[i].ip) .. "/" .. self.lpm4_ents[i].length
      assert(against[cidr] and against[cidr] == self.lpm4_ents[i].key, cidr .. " not found")
   end
end
function LPM4:add_random_entries (tab)
   local tab = tab or {
      [0] = 1,
      [10] = 50, [11] = 100, [12] = 250,
      [13] = 500, [14] = 1000, [15] = 1750,
      [16] = 12000, [17] = 8000, [18] = 13500,
      [19] = 26250, [20] = 40000, [21] = 43000,
      [22] = 75000, [23] = 65000, [24] = 350000,
      [25] = 1250, [26] = 1000, [27] = 500,
      [28] = 500, [29] = 1250, [30] = 150,
      [31] = 50, [32] = 1500
   }

   local count = 0
   for k,v in pairs(tab) do count = count + v end

   self:alloc("lpm4_ents", entry, count)
   local ents = self.lpm4_ents
   local r = rand(314159)
   local eoff = 0
   local addrs = {}

   for k,v in pairs(tab) do
      local mask = bit.bnot(2^(32-k)-1)
      local i = 0
      while i < v do
         r = rand(r)
         local ip = bit.band(r, mask)
         r = rand(r)
         ents[eoff].ip = ip
         ents[eoff].length = k
         ents[eoff].key = bit.band(r,0x7fff)

         if not addrs[ip * 64 + k] and ents[eoff].key ~= 0 then
            eoff = eoff + 1
            i = i + 1
         end
         addrs[ip * 64 + k] = true
      end
   end
   print("Adding " .. tostring(count) .. " random entries")
   self.entry_count = count
   for i=0, count-1 do
      self:add(ents[i].ip, ents[i].length, ents[i].key)
   end
   return self
end
function selftest ()
   local s = require("lib.lpm.lpm4_trie").LPM4_trie:new()
   s:add_string("10.0.0.0/24", 10)
   s:add_string("0.0.0.10/32", 11)
   assert(10 == s:search_bytes(ffi.new("uint8_t[4]", {10,0,0,0})))
   assert(11 == s:search_bytes(ffi.new("uint8_t[4]", {0,0,0,10})))
end
function LPM4:selftest (cfg, millions)
   assert(self, "selftest must be called with : ")
   local trusted = require("lib.lpm.lpm4_trie").LPM4_trie:new()
   trusted:add_random_entries()

   local f = self:new(cfg)
   f:add_random_entries()
   for i = 1,5 do
      f:build():verify(trusted:build())
      f:verify_entries_method()
      f:remove_random_entries()
      trusted:remove_random_entries()
   end

   local ptr = C.malloc(256*1024*1024)
   local f = self:new(cfg)
   local g = self:new(cfg)
   f:add_random_entries()
   f:build()
   f:alloc_store(ptr)
   g:alloc_load(ptr)
   g:verify(f)
   C.free(ptr)

   self:new(cfg):add_random_entries():benchmark(millions)
   print("selftest complete")
end
