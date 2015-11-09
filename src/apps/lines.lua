module(...,package.seeall)

--merge/split packets on line boundary and call a callback for each line.
--useful for implementing ASCII line-based protocols.

local ffi = require("ffi")

Lines = {}

function Lines:new (arg)
   assert(type(arg) == 'table' and arg.callback, 'callback required')
   return setmetatable({callback = arg.callback, pieces = {}}, {__index = self})
end

local function find(char, buf, len, start)
   local byte = char:byte()
   for i = start, len-1 do
      if buf[i] == byte then
         return i
      end
   end
end

function Lines:push ()
   local l = self.input.rx
   if l == nil then return end
   local t = self.pieces
   while not link.empty(l) do
      local p = link.receive(l)
      local i = 0
      while true do
         local j = find('\n', p.data, p.length, i)
         t[#t+1] = ffi.string(p.data + i, (j or p.length) - i)
         if j then
            self:callback(table.concat(t))
            t = {}
            self.pieces = t
            i = j + 1
            if i == p.length then
               break
            end
         else --line unfinished, keep receiving
            break
         end
      end
      packet.free(p)
   end
end


function selftest ()
   local t = {}
   local lines = Lines:new{callback = function(self, s)
      t[#t+1] = s
   end}
   lines.input = {}
   lines.input.rx= link.new("test")
   for i,s in ipairs{'li','ne1\nline','2\n','line3\n'} do
      local p = packet.allocate()
      ffi.copy(p.data, s, #s)
      p.length = #s
      link.transmit(lines.input.rx, p)
   end
   lines:push()
   for i,s in ipairs(t) do
      assert(t[i] == 'line'..i)
   end
end
