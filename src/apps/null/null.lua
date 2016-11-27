-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

Nullapp = {
}

function Nullapp:new (conf)
   local self = {}
   return setmetatable(self, {__index = Nullapp})
end

function Nullapp:push(dummy)
   local l = self.input.rx
   if l == nil then
      print("null: push: no link");
      return
   end
   while not link.empty(l) do
      local p = link.receive(l)
      print('null: sinking: ', p.length, lib.hexdump(ffi.string(p.data, p.length)))
      packet.free(p)
   end
end

function Nullapp:pull()
end
