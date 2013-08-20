-- port.lua -- Ethernet port abstraction

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local buffer = require("buffer")
local packet = require("packet")

-- Dictionary of ports that exist.
ports = {}

--- A port is a logical ethernet port.

Port = {}

function new (name, inputs, outputs, coroutine)
   local o = {name = name, inputs = inputs, outputs = outputs,
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
   local p = packet.allocate()
   -- But make it interesting: three iovecs in the packet.
   local b1, b2, b3 = buffer.allocate(), buffer.allocate(), buffer.allocate()
   for i = 0, b1.size-1 do b1.pointer[i] = 0xb1 end
   for i = 0, b2.size-1 do b2.pointer[i] = 0xb2 end
   for i = 0, b3.size-1 do b3.pointer[i] = 0xb3 end
   packet.add_iovec(p, b1, 10)
   packet.add_iovec(p, b2, 20)
   packet.add_iovec(p, b3, 30)
   C.usleep(1e6)
   repeat
      for i = 1,#inputs do
         local output = outputs[i]
         while output:can_transmit() do
            output:transmit(p)
         end
         output:sync_transmit()
      end
      C.usleep(10)
   until coroutine.yield("spam") == nil
   buffer.deref(buf)
end

-- Transmit and receive packets as quickly as possible in loopback mode.
function Port:loopback_test (options)
   local inputs, outputs = self.inputs, self.outputs
   options = options or {}
   local verify = options.verify
   local npackets = options.npackets or 100
   print("npackets",npackets)
   -- Allocate receive buffers
   for i = 1,#inputs do
      local input, output = inputs[i], outputs[i]
      input:sync_receive()
      for i = 1, npackets do
         assert(input:can_add_receive_buffer())
         input:add_receive_buffer(buffer.allocate())
      end
      for i = 1, npackets do
         local p = packet.allocate()
         local b = buffer.allocate()
         local len = 60
         packet.add_iovec(p, b, len)
         assert(output:can_transmit())
         output:transmit(p)
         assert(p.refcount == 2)
         packet.deref(p)
      end
      output:sync_transmit()
      assert(not input:can_receive())
   end
   -- Read back and write out all of the packets in a loop
   repeat
      for i = 1,#inputs do
         local input, output = inputs[i], outputs[i]
         input:sync_receive()
         while input:can_add_receive_buffer() do
            input:add_receive_buffer(buffer.allocate())
         end
         while input:can_receive() and output:can_transmit() do
            local p = input:receive()
            output:transmit(p)
            assert(p.refcount == 2)
            packet.deref(p)
         end
         output:sync_transmit()
      end
   until coroutine.yield("loopback") == nil
end

-- Echo receives packets and transmits the same packets back onto the
-- network. The receive queue is only processed when the transmit
-- queue has available space. Buffers are allocated and freed
-- dynamically.

function Port:echo ()
   local inputs, outputs = self.inputs, self.outputs
   repeat
      for i = 1,#inputs do
         local input, output = inputs[i], outputs[i]
         input:sync_receive()
         while input:can_receive() and output:can_transmit() do
            local p = input:receive()
            output:transmit(p)
            packet.deref(p)
         end
         while input:can_add_receive_buffer() do
            input:add_receive_buffer(buffer.allocate())
         end
         output:sync_transmit()
      end
      C.usleep(1)
   until coroutine.yield("echo") == nil
end

function selftest (options)
   print("selftest: port")
   options = options or {}
   local devices = options.devices
   assert(devices)
   local port = port.new("test", devices, devices)
   local program = options.program or Port.spam
   port.coroutine = coroutine.wrap(program)
   local finished = lib.timer((options.secs or 1) * 1e9)
   local start_time = C.get_time_ns()
   repeat
      port:run(port)
   until finished()
   local end_time = C.get_time_ns()
   local rx, tx = 0, 0
   local rxp, txp = 0, 0
   if options.report then
      -- Report traffic stats. XXX Currently specific to intel10g.
      for _,d in pairs(options.devices) do
         if d.s and d.s.GPRC then
            --      register.dump(d.r)
            rx = rx + d.s.GORCL() + d.s.GORCH() * 2^32
            tx = tx + d.s.GOTCL() + d.s.GOTCH() * 2^32
            rxp = rxp + d.s.GPRC()
            txp = txp + d.s.GPTC()
            register.dump(d.s, true)
         end
      end
      nanos = tonumber(end_time - start_time)
      io.write(("Transmit goodput: %3.2f Gbps %3.2f Mpps\n"):format(tonumber(tx)/nanos * 8, txp * 1000 / nanos))
      io.write(("Receive  goodput: %3.2f Gbps %3.2f Mpps\n"):format(tonumber(rx)/nanos * 8, rxp * 1000 / nanos))
   end
end

