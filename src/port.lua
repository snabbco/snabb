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
   local input, output = self.input, self.output
   -- Keep it simple: use one buffer for everything.
   local buf = buffer.allocate()
   buf.size = 32
   repeat
      input.sync_receive()
      while input.can_receive() do
	 input.receive()
      end
      while output.can_transmit() do
	 output.transmit(buf)
      end
      while input.can_add_receive_buffer() do
	 input.add_receive_buffer(buf)
      end
      output.sync_transmit()
      C.usleep(100000)
   until coroutine.yield("spam") == nil
   buffer.deref(buf)
end

-- Transmit and receive packets as quickly as possible in loopback mode.
function Port:loopback_test (options)
   local input, output = self.input, self.output
   options = options or {}
   local verify = options.verify
   local npackets = options.npackets or 10000
   print("npackets",npackets)
   C.usleep(100000)
   -- Allocate receive buffers
   input.sync_receive()
   for i = 1, npackets do
      assert(input.can_add_receive_buffer())
      input.add_receive_buffer(buffer.allocate())
   end
   -- Fill the pipe with transmited packets
   for i = 1, npackets do
      local buf = buffer.allocate()
      buf.size = 100
      assert(output.can_transmit())
      output.transmit(buf)
   end
   output.sync_transmit()
   assert(not input.can_receive())
   -- Read back and write out all of the packets in a loop
   repeat
      input.sync_receive()
      while input.can_add_receive_buffer() do
         input.add_receive_buffer(buffer.allocate())
      end
      while input.can_receive() and output.can_transmit() do
         local buf = input.receive()
         output.transmit(buf)
         buffer.deref(buf)
      end
      output.sync_transmit()
--      C.usleep(1000)
   until coroutine.yield("loopback") == nil
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
         local buf = input.receive()
         output.transmit(buf)
         buffer.deref(buf)
      end
      while input.can_add_receive_buffer() do
	 input.add_receive_buffer(buffer.allocate())
      end
      output.sync_transmit()
   until coroutine.yield("echo") == nil
end

function selftest (options)
   print("selftest: port")
   options = options or {}
   local device = options.device
   if device == nil then
      device = require("virtio").new("snabb%d")
      device.init()
   end
   local port = port.new("test", device, device)
   local program = options.program or Port.spam
   port.coroutine = coroutine.wrap(program)
   local finished = lib.timer((options.secs or 1) * 1e9)
   repeat
      port:run(port)
   until finished()
end

