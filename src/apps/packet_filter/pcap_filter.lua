module(...,package.seeall)

package.path = package.path .. ";../deps/pflua/src/?.lua"

local ffi = require("ffi")
local C = ffi.C
local bit = require("bit")

local app = require("core.app")
local link = require("core.link")
local lib = require("core.lib")
local packet = require("core.packet")
local config = require("core.config")

local pcap = require("apps.pcap.pcap")
local basic_apps = require("apps.basic.basic_apps")

local pflua = require("pf")

local verbose = false

assert(ffi.abi("le"), "support only little endian architecture at the moment")
assert(ffi.abi("64bit"), "support only 64 bit architecture at the moment")

PacketFilter = {}

-- TODO: Since compilation process is relatively expensive, we could fork to 
-- compile in a subprocess, implement a cache, etc
function PacketFilter:new (filters)
   assert(filters)
   assert(#filters > 0)

   for i,filter in ipairs(filters) do
      filters[i] = "("..filter..")"
   end
   local filter = table.concat(filters, " or ")
   local o = {
      conform = pflua.compile_filter(filter)
   }
   return setmetatable(o, { __index = PacketFilter })
end

function PacketFilter:push ()
   local i = assert(self.input.input or self.input.rx, "input port not found")
   local o = assert(self.output.output or self.output.tx, "output port not found")

   local packets_tx = 0
   local max_packets_to_send = link.nwritable(o)
   if max_packets_to_send == 0 then
      return
   end

   local nreadable = link.nreadable(i)
   for n = 1, nreadable do
      local p = link.receive(i)

      if self.conform(p.data, p.length) then
         link.transmit(o, p)
      else
         packet.free(p)
      end
   end
end
