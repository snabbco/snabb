module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local ctable = require("lib.ctable_perfect")

tunnel = {
   config = {
      vcs = { default = {} },
      ancillary_data = {
         config = {
            local_addr = { required = true },
            remote_addr = { required = true }
         }
      }
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
   local o = { headers = {}, keys = {} }

   o.header_size = size
   local key_t = ffi.typeof("uint8_t [$]", o.header_size)
   o.key_ptr_t = ffi.typeof("$*", key_t)

   local keys_list = {}
   for vc_id, arg in pairs(config.vcs) do
      local name = "vc_"..vc_id
      local config = lib.parse(arg, params)
      local header_in, header_out = create_headers_fn(vc_id, config)
      local key = key_t()
      ffi.copy(key, ffi.cast(o.key_ptr_t, header_in:header_ptr()), o.header_size)
      table.insert(keys_list, key)
      o.keys[name] = key
      o.headers[name] = header_out
   end

   o.ancillary_data = config.ancillary_data

   o.discard = link.new(name.."_discard")
   local default_value = self.value_t()
   default_value.link = o.discard
   o.ctab = ctable.new({
         key_type = key_t,
         value_type = self.value_t,
         keys = keys_list,
         default_value = default_value })

   o.logger = lib.logger_new({ module = name })
   o.header_scratch = class:new()
   o.handle_unknown_header_fn = unknown_header_fn

   return setmetatable(o, { __index = tunnel })
end

function tunnel:link (mode, dir, name, l)
   if mode == 'unlink' or name == "south" then return end
   if dir == 'output' then
      local key = assert(self.keys[name])
      local value = self.value_t()
      value.link = l
      value.shift = self.header_size
      self.ctab:update(key, value)
   else
      return self.prepend, ffi.cast("uint8_t *", self.headers[name]:header_ptr())
   end
end

function tunnel:prepend (lin, header)
   local sout = self.output.south
   for _ = 1, link.nreadable(lin) do
      local p = packet.prepend(link.receive(lin), header, self.header_size)
      link.transmit(sout, p)
   end
end

function tunnel:push (sin)
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
      self:handle_unknown_header_fn(p, self.ancillary_data)
      packet.free(p)
   end
end
