
local ffi = require('ffi')
local S = require('syscall')
local band = require("bit").band
local lib = require('core.lib')
local shm = require('core.shm')
local packet = require('core.packet')

ffi.cdef [[
   typedef struct {
      struct packet *packets[LINK_RING_SIZE];
      int write, read;

      double txbytes, rxbytes, txpackets, rxpackets, txdrop;
      int receiving_app, receiving_pid;
      bool has_new_data;
   } inter_link_t;
]]

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


function inter_link:transmit(p)
   if self:full() then
      self.txdrop = self.txdrop + 1
      p:free()
   else
      local prevPkt = self.packets[self.write]
      if prevPkt ~= nil then prevPkt:free() end
      self.packets[self.write] = p
      self.write = step(self.write)
      self.txpackets = self.txpackets + 1
      self.txbytes   = self.txbytes + p.length
      self.has_new_data = true
   end
end


function inter_link:empty()
   return self.read == self.write
end


function inter_link:receive()
   local p = self.packets[self.read]
   self.packets[self.read] = packet.allocate()
   self.read = step(self.read)

   self.rxpackets = self.rxpackets + 1
   self.rxbytes   = self.rxbytes + p.length
   return p
end


return ffi.metatype('inter_link_t', inter_link)
