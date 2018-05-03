module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")

ffi.cdef([[
void free(void *ptr);
void *malloc(int size);
]])

LPM = {}

function LPM:new()
  return setmetatable({ alloc_map = {} }, { __index = self })
end
function LPM:alloc (name, ctype, count, idx)
    local idx = idx or 0
    idx = idx - 1
    local heap = {}
    local count = count or 0

    local function realloc (size)
      if size == 0 then size = 1 end
      local bytes = ffi.sizeof(ctype) * size
      local ptr_t = ffi.typeof("$*", ctype)
      local ptr = assert(C.malloc(bytes))
      ffi.fill(ptr, bytes)
      ptr = ffi.cast(ptr_t, ptr)
      if self[name] then
        ffi.copy(ptr, self[name], ffi.sizeof(ctype) * count)
      end
      self[name] = ffi.gc(ptr, C.free)
      count = size
    end

    self[name .. "_type"] = function() return ctype end
    self[name .. "_length"] = function() return count end
    self[name .. "_free"] = function(self, idx) table.insert(heap, idx) end
    self[name .. "_grow"] = function(self, factor) realloc(count * (factor or 2)) end
    self[name .. "_load"] = function(self, ptr, bytelength)
      count = bytelength / ffi.sizeof(ctype)
      self[name] = ptr
      realloc(count)
    end
    self[name .. "_store"] = function(self, ptr)
      local bytes = ffi.sizeof(ctype) * count
      ffi.copy(ptr, self[name], bytes)
      return bytes
    end

    self[name .. "_new"] = function()
      if table.getn(heap) == 0 then
        if idx + 1 == count then
          realloc(count * 2)
        end
        idx = idx + 1
        return idx
      else
        return table.remove(heap)
      end
    end

    if count > 0 then
      realloc(count)
    end
    return self
end
function LPM:alloc_store(bytes)
  local bytes = ffi.cast("uint8_t *", bytes)
  for _,k in pairs(self.alloc_storable) do
    local lenptr = ffi.cast("uint64_t *", bytes)
    lenptr[0] = self[k .. "_store"](self, bytes + ffi.sizeof("uint64_t"))
    bytes = bytes + lenptr[0] + ffi.sizeof("uint64_t")
  end
end
function LPM:alloc_load(bytes)
  local bytes = ffi.cast("uint8_t *", bytes)
  for _,k in pairs(self.alloc_storable) do
    local lenptr = ffi.cast("uint64_t *", bytes)
    self[k .. "_load"](self, bytes + ffi.sizeof("uint64_t"), lenptr[0])
    bytes = bytes + lenptr[0] + ffi.sizeof("uint64_t")
  end
end
function selftest ()
  local s = LPM:new()
  s:alloc("test", ffi.typeof("uint64_t"), 2)
  assert(s:test_new() == 0)
  assert(s:test_new() == 1)
  assert(s:test_new() == 2)
  assert(s:test_new() == 3)
  assert(s:test_new() == 4)
  assert(s:test_new() == 5)
  assert(s:test_new() == 6)
  s:test_free(4)
  s:test_free(3)
  s:test_free(2)
  s:test_free(5)
  assert(s:test_new() == 5)
  assert(s:test_new() == 2)
  assert(s:test_new() == 3)
  assert(s:test_new() == 4)
  assert(s:test_new() == 7)
  assert(s:test_type() == ffi.typeof("uint64_t"))
  assert(s:test_length() == 8)
  for i = 0, 7 do s.test[i] = i end
  s:test_grow()
  for i =0,7 do assert(s.test[i] == i) end
  assert(s:test_length() == 16)
  s:test_grow(3)
  assert(s:test_length() == 48)

  local ptr = C.malloc(1024 * 1024)
  local tab = {}
  local ents = { "t1", "t2", "t3", "t4" }
  for i=1,3 do
    tab[i] = LPM:new()
    tab[i].alloc_storable = ents
    tab[i]:alloc("t1", ffi.typeof("uint8_t"), 16)
    tab[i]:alloc("t2", ffi.typeof("uint16_t"), 16)
    tab[i]:alloc("t3", ffi.typeof("uint32_t"), 16)
    tab[i]:alloc("t4", ffi.typeof("uint64_t"), 16)
  end
  for _, t in pairs(ents) do
    for j=0,127 do
      tab[1][t][ tab[1][t.."_new"]() ] = math.random(206)
    end
  end

  tab[1]:alloc_store(ptr)
  tab[2]:alloc_load(ptr)
  for _, t in pairs(ents) do
    for j=0,127 do
      assert(tab[1][t][j] == tab[2][t][j])
    end
  end

  C.free(ptr)

end
