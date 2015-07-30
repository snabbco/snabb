
local ffi = require('ffi')
local S = require('syscall')
local band = require("bit").band
local lib = require('core.lib')
local shm = require('core.shm')
local packet = require('core.packet')

ffi.cdef [[
   typedef struct {
      struct packet *packets[LINK_RING_SIZE];
      struct packet *ret_pks[LINK_RING_SIZE];
      int write, read;

      struct {
         double txbytes, rxbytes, txpackets, rxpackets, txdrop;
      } stats;
      int receiving_app, receiving_pid;
      bool has_new_data;
   } inter_link_t;

   typedef struct {
      struct packet *packets[LINK_RING_SIZE];
      inter_link_t *link;
      int head, tail;
   } front_buf;
]]

local size = ffi.C.LINK_RING_SIZE
local mask = ffi.C.LINK_RING_SIZE-1
local function step(n) return band(n+1, mask) end

local inter_link = {}
inter_link.__index = inter_link


function inter_link:__new(name)
   if ffi.istype(self, name) then return name end
   return shm.map(('//%d/links/%s'):format(S.getpgid(),name), self)
end


function inter_link:full()
   return step(self.write) == self.read
end

function inter_link:nwritable()
   return band(self.read - self.write - 1, mask)
end


function inter_link:transmit(p)
--    if self:full() then
--       self.txdrop = self.txdrop + 1
--       p:free()
--    else
      if self.ret_pks[self.write] ~= nil then
         self.ret_pks[self.write]:free()
      end
      self.packets[self.write] = p
      self.write = step(self.write)
      self.stats.txpackets = self.stats.txpackets + 1
      self.stats.txbytes   = self.stats.txbytes + p.length
      self.has_new_data = true
--    end
end


function inter_link:front_buf()
   return ffi.new('front_buf', {
      link = self,
      head = 0, tail = 0;
   })
end


function inter_link:empty()
   return self.read == self.write
end

function inter_link:nreadable()
   return band(self.write - self.read, mask)
end


function inter_link:receive()
   local p = self.packets[self.read]
   self.ret_pks[self.read] = (self.receiving_pid ~= 0) and packet.allocate() or nil
   self.read = step(self.read)

   self.stats.rxpackets = self.stats.rxpackets + 1
   self.stats.rxbytes   = self.stats.rxbytes + p.length
   return p
end


local front_buf = {}
front_buf.__index = front_buf

function front_buf:add(p)
   if step(self.head) == self.tail then
      local l = self.link
      local lw = l.write
      local n = math.min(band(self.head-self.tail, mask), l:nwritable())
      for i = 1, n do
         if l.ret_pks[lw] ~= nil then l.ret_pks[lw]:free() end
         l.packets[lw] = self.packets[self.tail]
         lw = step(lw)
         self.tail = step(self.tail)
      end
      l.write = lw
      l.stats.txpackets = l.stats.txpackets + n
   end
   self.packets[self.head] = p
   self.head = step(self.head)
end

ffi.metatype('front_buf', front_buf)

return ffi.metatype('inter_link_t', inter_link)
