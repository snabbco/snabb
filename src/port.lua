-- port.lua -- Ethernet port abstraction

module(...,package.seeall)

local C = require("ffi").C
local buffer = require("buffer")

-- Dictionary of ports that exist.
ports = {}

--- A port is a logical ethernet port.

Port = {}

function new (name, input, output, coroutine)
   local o = {name = name, input = input, output = output,
	      coroutine = coroutine, state = "start"}
   setmetatable(o, {__index = Port,
		    __tostring = Port.tostring})
   ports[name] = o
   return o
end

function Port:tostring () return "Port<"..self.name..">" end

function Port:selftest ()
   self:spam()
end

function Port:run (...)
   if self.coroutine then
      if self.coroutine(...) == nil then self.coroutine = nil end
   end
end

--- Spamming is sending and receiving in a tight loop using only one
--- packet buffer.

function Port:spam ()
   local inputs, outputs = self.inputs, self.outputs
   -- Keep it simple: use one buffer for everything.
   local buf = buffer.allocate()
   buf.size = 32
   repeat
      for _,input in pairs(inputs) do
         input.sync_receive()
         while input.can_receive() do
            input.receive()
         end
         while input.can_add_receive_buffer() do
            input.add_receive_buffer(buf)
         end
      end
      for _,output in pairs(outputs) do
         while output.can_transmit() do
            output.transmit(buf)
         end
         output.sync_transmit()
      end
      C.usleep(100000)
   until coroutine.yield("spam") == nil
   buffer.deref(buf)
end

-- Echo receives packets and transmits the same packets back onto the
-- network. The receive queue is only processed when the transmit
-- queue has available space. Buffers are allocated and freed
-- dynamically.

function Port:echo ()
   local input, output = self.input, self.output
   repeat
      self.input.sync_receive()
      while input.can_receive() and output.can_transmit() do
	 local addr, len = input.receive()
	 output.transmit(addr, len)
      end
      while input.can_add_receive_buffer() do
	 input.add_receive_buffer(buffer.allocate())
      end
      while output.can_reclaim_buffer() do
	 buffer.free(output.reclaim_buffer())
      end
      output.sync_transmit()
   until coroutine.yield("echo") == nil
end

function selftest (options)
   print("selftest: port")
   options = options or {}
   local devices = options.devices
   if devices == nil then
      devices = {require("virtio").new("snabb%d")}
      for _,device in pairs(devices) do
         device.init()
      end
   end
   local port = port.new("test", devices, devices)
   local program = options.program or Port.spam
   port.coroutine = coroutine.wrap(program)
   local finished = lib.timer((options.secs or 1) * 1e9)
   repeat
      port:run(port)
   until finished()
end

