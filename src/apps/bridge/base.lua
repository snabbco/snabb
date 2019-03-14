-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local logger = require("lib.logger")

bridge = subClass(nil)
bridge._name = "base bridge"
bridge.config = {
   ports = { required = true },
   split_horizon_groups = { default = {} },
   config = { default = {} },
}

function bridge:new (conf)
   assert(self ~= bridge, "Can't instantiate abstract class "..self:name())
   local o = bridge:superClass().new(self)
   o.ports = {}
   o.logger = logger.new({ module = "bridge" })
   o.box = ffi.new("struct packet *[1]")
   o.discard = link.new("discard")

   local index = 0
   local function add_port(name, group)
      assert(not o.ports[name], "Duplicate definition of port "..name)
      o.ports[name] = {
         index = index,
         group = group,
         queue = link.new("queue_"..name),
      }
      o.max_index = index
      index = index + 1
   end
   for _, name in ipairs(conf.ports) do
      add_port(name)
   end
   for group, ports in pairs(conf.split_horizon_groups) do
      for _, name in ipairs(ports) do
         add_port(name, group)
      end
   end

   egress_t = ffi.typeof("struct link *[$]", index)
   local function mk_egress_table()
      local t = egress_t()
      for index = 0, index - 1 do
         t[index] = o.discard
      end
      return t
   end
   for _, port in pairs(o.ports) do
      port.egress = mk_egress_table()
   end

   return o
end

function bridge:link (mode, dir, name, link)
   local this_port = assert(self.ports[name],
                            "Undeclared port: "..name)
   if dir == "output" then
      for _, port in pairs(self.ports) do
         if ((port.group == nil or port.group ~= this_port.group)
               and port.index ~= this_port.index) then
            port.egress[this_port.index] = link
         end
      end
   else
      return nil, this_port
   end
end
