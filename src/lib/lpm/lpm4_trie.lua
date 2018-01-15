module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local lpm4 = require("lib.lpm.lpm4")
local coro = require("coroutine")
local bit = require("bit")
local ip4 = require("lib.lpm.ip4")
local masked = ip4.masked
local get_bit = ip4.get_bit
local commonlength = ip4.commonlength

LPM4_trie = setmetatable({ alloc_storable = { "lpm4_trie" } }, { __index = lpm4.LPM4 })

local trie = ffi.typeof([[
  struct {
    uint32_t ip;
    int32_t key;
    int32_t length;
    int32_t down[2];
  }
]])

function LPM4_trie:new()
  local self = lpm4.LPM4.new(self)
  local count = 5000000
  self:alloc("lpm4_trie", trie, count, 1)
  return self
end

function LPM4_trie:get_node()
  local ts = self.lpm4_trie
  local t = self:lpm4_trie_new()
  ts[t].ip = 0
  ts[t].key = 0
  ts[t].down[0] = 0
  ts[t].down[1] = 0
  return t
end
function LPM4_trie:return_node(t)
  self:lpm4_trie_free(t)
end

function LPM4_trie:set_trie(t, ip, length, key, left, right)
  local left = left or 0
  local right = right or 0
  local ts = self.lpm4_trie
  ts[t].ip = masked(ip, length)
  ts[t].length = length
  ts[t].key = key
  ts[t].down[0] = left
  ts[t].down[1] = right
  -- This is great for debugging but for some reason has an unreasonably
  -- high performance hit :S
  -- FIXME
  --self:debug_print(string.format("setting %4d %13s/%-2d  %4d %4d %4d", t,
  --                         self:ip_to_string(ts[t].ip), length, key,
  --                         ts[t].down[0], ts[t].down[1]))
end
function LPM4_trie:debug_print(str)
  if self.debug then print(str) end
end
function LPM4_trie:add(ip, length, key)
  local ts = self.lpm4_trie
  local t = 0
  while true do
    if ts[t].ip == ip and ts[t].length == length then
      -- prefix already in trie, just update it
      self:set_trie(t, ip, length, key, ts[t].down[0], ts[t].down[1])
      return
    elseif ts[t].ip == ip and ts[t].length > length then
      -- ts[t] is more specific than ip/length that is being added
      -- add ip / length as the parent of ts[t]
      local new = self:get_node()
      self:set_trie(new, ts[t].ip, ts[t].length, ts[t].key, ts[t].down[0], ts[t].down[1])
      self:set_trie(t, ip, length, key, new)
      return
    elseif ts[t].ip == masked(ip, ts[t].length) then
      -- ts[t] is on the path to the node we want
      local b = get_bit(ip, ts[t].length)
      if ts[t].down[b] ~= 0 then
        -- keep going down the tree
          t = ts[t].down[b]
      else
        -- add a leaf
        ts[t].down[b] = self:get_node()
        self:set_trie(ts[t].down[b], ip, length, key)
        return
      end
    else
      -- A leaf node has been found, that partially matches ip
      local new = self:get_node()
      -- copy the leaf into new
      self:set_trie(new, ts[t].ip, ts[t].length, ts[t].key,
        ts[t].down[0], ts[t].down[1])
      -- turn the leaf into an internal node, that has no key
      local clength = math.min(commonlength(ts[t].ip, ip), length)
      self:set_trie(t, ip, clength, 0)

      if ts[t].length == length then
        local b = get_bit(ts[new].ip, ts[t].length)
      -- if the internal node is the ip/length to add set the key
         ts[t].key = key
         ts[t].down[b] = new
      else
        -- otherwise create a new leaf for it
        local b = get_bit(ip, ts[t].length)
        local new2 = self:get_node()
        self:set_trie(new2, ip, length, key)
        -- attach it to the internal node
        ts[t].down[b] = new2
        -- attach the old leaf to the internal node
        ts[t].down[math.abs(b-1)] = new
      end
      return
    end
  end
end
function LPM4_trie:remove(ip, length)

  local ts = self.lpm4_trie
  local t = 0
  local prevt
  while true do
    if ts[t].ip == ip and ts[t].length == length then
      -- Delete the t
      if ts[t].down[0] == 0 and ts[t].down[1] == 0 then
        -- there are no children
        if t == 0 then
          -- it's the root of the tree just remove the key
          ts[t].key = 0
          return
        elseif ts[prevt].down[0] == t then
          -- it's the left hand leaf delete parent ptr
          ts[prevt].down[0] = 0
        else
          -- it's the right hand leaf delete parent ptr
          ts[prevt].down[1] = 0
        end
        self:return_node(t)
        return
      elseif ts[t].down[0] ~= 0 and ts[t].down[1] ~= 0 then
        -- it's an internal node just remove the key
        ts[t].key = 0
        return
      elseif ts[t].down[0] == 0 then
        -- it has a right hand leaf pull that up the tree
        local u = ts[t].down[1]
        local ue = ts[u]
        self:set_trie(t, ue.ip, ue.length, ue.key, ue.down[0], ue.down[1])
        self:return_node(u)
        return
      elseif ts[t].down[1] == 0 then
        -- it has a left hand leaf pull that up the tree
        local u = ts[t].down[0]
        local ue = ts[u]
        self:set_trie(t, ue.ip, ue.length, ue.key, ue.down[0], ue.down[1])
        self:return_node(u)
        return
      end
    end
    -- keep track of the parent
    prevt = t
    -- traverse the tree
    local b = get_bit(ip, ts[t].length)
    if ts[t].down[b] ~= 0 then
      t = ts[t].down[b]
    else
      return
    end
  end

end

function LPM4_trie:entries()
  local ts = self.lpm4_trie
  local ent = ffi.new(lpm4.entry)
  -- carry out a preorder tree traversal which sorts by ip and tie breaks with
  -- length.
  -- Use coroutines https://www.lua.org/pil/9.3.html
  local function traverse(t)
    local t = t or 0
    if self.debug then
      print(string.format("%15s/%-2d %6d %6d %6d %6d",
        ip4.tostring(ts[t].ip),
        ts[t].length,
        ts[t].key,
        t,
        ts[t].down[0],
        ts[t].down[1]
      ))
    end
    if ts[t].key ~= 0 then
      ent.ip, ent.length, ent.key = ts[t].ip, ts[t].length, ts[t].key
      coro.yield(ent)
    end
    if ts[t].down[0] ~= 0 then
      traverse(ts[t].down[0])
    end
    if ts[t].down[1] ~= 0 then
      traverse(ts[t].down[1])
    end
  end
  return coro.wrap(function() traverse() end)
end
function LPM4_trie:has_child(ip, length)
  local ts = self.lpm4_trie
  local t = self:search_trie(ip, length, true)
  if ts[t].ip == ip and ts[t].length == length then
    return ts[t].down[0] ~= 0 or ts[t].down[1] ~= 0
  end
  assert(ts[t].length < length)
  local b = get_bit(ip, ts[t].length)
  if ts[t].down[b] == 0 then
    return false
  elseif masked(ts[ts[t].down[b]].ip, length) == masked(ip, length) then
    return true
  end
end
function LPM4_trie:search_trie(ip, length, internal)
  local ts = self.lpm4_trie
  local t = 0
  local length = length or 32
  local prevt
  local internal = internal or false
  while true do
    if masked(ts[t].ip, ts[t].length) ~= masked(ip, ts[t].length) then
      return prevt
    end
    if ts[t].length > length then
      return prevt
    end
    if ts[t].length == 32 then return t end
    if ts[t].key ~= 0 or internal then prevt = t end
    local b = get_bit(ip, ts[t].length)
    if ts[t].down[b] ~= 0 then
      t = ts[t].down[b]
    else
      return prevt
    end
  end
end
function LPM4_trie:search_entry(ip)
  local indx = self:search_trie(ip)
  if indx == nil then return end
  local ent = ffi.new(lpm4.entry)
  local ts = self.lpm4_trie
  ent.ip = ts[indx].ip
  ent.length = ts[indx].length
  ent.key = ts[indx].key
  return ent
end
function selftest_has_child()
  local f = LPM4_trie:new()
  f:add_string("192.0.0.0/8", 1)
  f:add_string("192.64.0.0/11", 2)
  f:add_string("192.32.0.0/11", 3)
  assert(f:has_child(ip4.parse("128.0.0.0"),1) == true)
  assert(f:has_child(ip4.parse("192.0.0.0"),8) == true)
  assert(f:has_child(ip4.parse("192.0.0.0"),8) == true)
  assert(f:has_child(ip4.parse("192.64.0.0"),10) == true)
end

function selftest()
  local f = LPM4_trie:new()
  assert(1 == f:get_node())
  assert(2 == f:get_node())
  assert(3 == f:get_node())
  f:return_node(1)
  assert(1 == f:get_node())
  f:return_node(2)
  f:return_node(3)
  f:return_node(1)
  assert(1 == f:get_node())
  assert(3 == f:get_node())
  assert(2 == f:get_node())

  f = LPM4_trie:new()
  f:add_string("0.0.0.0/0",700)
  f:add_string("128.0.0.0/8",701)
  f:add_string("192.0.0.0/8",702)
  f:add_string("192.0.0.0/16",703)
  f:add_string("224.0.0.0/8",704)

  assert(700 == f:search_string("127.1.1.1"))
  assert(701 == f:search_string("128.1.1.1"))
  assert(702 == f:search_string("192.168.0.0"))
  assert(703 == f:search_string("192.0.0.1"))
  assert(704 == f:search_string("224.1.1.1"))
  assert(700 == f:search_string("255.255.255.255"))
  assert(f.lpm4_trie[f:search_trie(ip4.parse("0.0.0.0"),0)].key == 700)
  assert(f.lpm4_trie[f:search_trie(ip4.parse("128.1.1.1"),0)].key == 700)
  assert(f.lpm4_trie[f:search_trie(ip4.parse("128.1.1.1"),8)].key == 701)
  assert(f.lpm4_trie[f:search_trie(ip4.parse("192.0.0.1"),8)].key == 702)
  assert(f.lpm4_trie[f:search_trie(ip4.parse("192.0.0.0"),16)].key == 703)
  assert(f.lpm4_trie[f:search_trie(ip4.parse("255.255.255.255"),32)].key == 700)

  f:remove_string("192.0.0.0/8")
  f:remove_string("224.0.0.0/8")
  assert(700 == f:search_string("127.1.1.1"))
  assert(701 == f:search_string("128.1.1.1"))
  assert(700 == f:search_string("192.168.0.0"))
  assert(703 == f:search_string("192.0.0.1"))
  assert(700 == f:search_string("224.1.1.1"))
  assert(700 == f:search_string("255.255.255.255"))

  f = LPM4_trie:new()
  f:add_string("0.0.0.0/0", 1118)
  f:add_string("148.102.0.0/15", 22405)
  f:add_string("148.107.83.0/24", 19626)
  f:add_string("148.96.0.0/12", 22604)
  assert(1118 == f:search_string("1.1.1.1"))
  assert(22405 == f:search_string("148.102.0.1"))
  assert(19626 == f:search_string("148.107.83.1"))
  assert(22604 == f:search_string("148.96.0.0"))

  f = LPM4_trie:new()
  f:add_string("0.0.0.0/0", 1118)
  f:add_string("135.86.103.0/24", 8758)
  f:add_string("135.86.64.0/18", 5807)
  assert(1118 == f:search_string("1.1.1.1"))
  assert(8758 == f:search_string("135.86.103.1"))
  assert(5807 == f:search_string("135.86.110.232"))

  f = LPM4_trie:new()
  f:add_string("0.0.0.0/0", 1118)
  f:add_string("84.125.102.0/24", 25928)
  f:add_string("84.125.96.0/19", 7065)
  assert(1118 == f:search_string("1.1.1.1"))
  assert(7065 == f:search_string("84.125.96.0"))
  assert(7065 == f:search_string("84.125.120.73"))
  assert(25928 == f:search_string("84.125.102.0"))

  f = LPM4_trie:new()
  f:add_string("150.171.100.0/24", 29171)
  f:add_string("150.171.108.0/22", 21173)
  f:add_string("150.171.96.0/19", 12159)
  assert(29171 == f:search_string("150.171.100.1"))
  assert(21173 == f:search_string("150.171.108.1"))
  assert(12159 == f:search_string("150.171.96.1"))

  selftest_has_child()

  f = LPM4_trie:new()
  f:add_string("0.0.0.10/32", 10)
  assert(f:search_string("0.0.0.10") == 10)

  -- LPM4_trie is slow, compared to the other algorithms
  -- run 1000,000 lookups to benchmark
  LPM4_trie:selftest({}, 1000000)
end
