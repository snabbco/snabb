module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local ctable = require("lib.ctable_perfect")

tunnel = {
   config = {
      vcs = { default = {} },
      logger = { default = nil },
   }
}

tunnel.value_t = ffi.typeof[[
  struct {
    struct link *link;
    uint8_t shift;
  }
]]

function tunnel:_new (config, name, class, size, params,
                      create_headers_fn, unknown_header_fn)
   local o = { vcs = {},
               vcs_by_name = {},
               keys_by_name = {} }

   o.header_size = size
   local key_t = ffi.typeof("uint8_t [$]", o.header_size)
   o.key_ptr_t = ffi.typeof("$*", key_t)

   local keys = {}
   for vc_id, arg in pairs(config.vcs) do
      local config = lib.parse(arg, params)
      local header_in, header_out = create_headers_fn(vc_id, config)
      local vc = {
         header = header_out,
         header_ptr = ffi.cast("uint8_t *", header_out:header_ptr())
      }
      local name = "vc_"..vc_id
      table.insert(o.vcs, vc)
      o.vcs_by_name[name] = vc
      local key = key_t()
      ffi.copy(key, ffi.cast(o.key_ptr_t, header_in:header_ptr()), o.header_size)
      table.insert(keys, key)
      o.keys_by_name[name] = key
   end

   o.nvcs = #o.vcs
   o.discard = link.new(name.."_discard")
   local default_value = self.value_t()
   default_value.link = o.discard
   o.ctab = ctable.new({
         key_type = key_t,
         value_type = self.value_t,
         keys = keys,
         default_value = default_value })

   o.logger = lib.logger_new({ module = name })
   o.header_scratch = class:new()
   o.handle_unknown_header_fn = unknown_header_fn

   return setmetatable(o, { __index = tunnel })
end

function tunnel:link ()
   local value = self.value_t()
   value.shift = self.header_size
   for name, l in pairs(self.output) do
      if type(name) == "string" and name ~= "south" then
         local key = assert(self.keys_by_name[name])
         value.link = l
         self.ctab:update(key, value)
      end
   end
   for name, l in pairs(self.input) do
      if type(name) == "string" and name ~= "south" then
         self.vcs_by_name[name].link_in = l
      end
   end
end

local function vc_input (self, i, sout)
      local vc = self.vcs[i]

      for _ = 1, link.nreadable(vc.link_in) do
         local p = link.receive(vc.link_in)
         p = packet.prepend(p, vc.header_ptr, self.header_size)
         link.transmit(sout, p)
      end
end

function tunnel:push ()
   local sin = self.input.south
   local sout = self.output.south

   for _ = 1, link.nreadable(sin) do
      local p = link.receive(sin)
      assert(p.length > 0)
      local key = ffi.cast(self.key_ptr_t, p.data)
      local entry = self.ctab:lookup_ptr(ffi.cast("uint8_t *", key))
      link.transmit(entry.value.link, packet.shiftleft(p, entry.value.shift))
   end

   local discard = self.discard
   for _ = 1, link.nreadable(discard) do
      local p = link.receive(discard)
      self:handle_unknown_header_fn(p)
      packet.free(p)
   end

   if self.nvcs >= 3 then
      for i = 1, self.nvcs do
         vc_input(self, i, sout)
      end
   else
      if self.nvcs >= 1 then
         vc_input(self, 1, sout)
      end
      if self.nvcs >= 2 then
         vc_input(self, 2, sout)
      end
   end
end
