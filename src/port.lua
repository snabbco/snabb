-- port.lua -- Ethernet port abstraction

module(...,package.seeall)

require("pci")
local C = require("ffi").C
local buffer = require("buffer")

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
   if self.program then
      if self.program(...) == nil then self.program = nil end
   end
end

--- Spamming is sending and receiving in a tight loop using only one
--- packet buffer.

function Port:spam ()
   local inputs, outputs = self.inputs, self.outputs
   -- Keep it simple: use one buffer for everything.
   local buf = buffer.allocate()
   buf.refcount = 0
   buf.size = 50
   return function ()
--             if false then
                for _,input in ipairs(inputs) do
                   while input.can_receive() do
                      input.receive()
                   end
                   if (math.random() > 0.9) then 
                      while input.can_add_receive_buffer() do
                         input.add_receive_buffer(buf)
                      end
                   end
                end
--             end
             for _,output in ipairs(outputs) do
--                for i = 1,output.how_many_can_transmit() do
--                   output.transmit(buf)
--                end
--                if false then
                   while output.can_transmit() do
                      output.transmit(buf)
                   end
--                end
                output.sync_transmit()
             end
             return true
          end
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
      devices = {}
      for _,d in pairs(pci.devices) do
         if d.usable then
            local driver = pci.open_device(d.pciaddress, d.driver)
            driver.open()
            driver.enable_mac_loopback()
            driver.wait_linkup()
            table.insert(devices, driver)
         end
      end
   end
   local port = port.new("test", devices, devices)
   local program = options.program or port:spam()
   port.program = program
   local finished = lib.timer((options.secs or 10) * 1e9)
   local start_time = C.get_time_ns()
   repeat
      port:run(port)
   until finished()
   local end_time = C.get_time_ns()
   local rx, tx = 0, 0
   local rxp, txp = 0, 0
   for _,d in pairs(devices) do
--      register.dump(d.s, true)
--      register.dump(d.r)
      rx = rx + d.s.GORCL() + d.s.GORCH() * 2^32
      tx = tx + d.s.GOTCL() + d.s.GOTCH() * 2^32
      rxp = rxp + d.s.GPRC()
      txp = txp + d.s.GPTC()
   end
   nanos = tonumber(end_time - start_time)
   io.write(("Transmit goodput: %3.2f Gbps %3.2f Mpps\n"):format(tonumber(tx)/nanos * 8, txp * 1000 / nanos))
   io.write(("Receive  goodput: %3.2f Gbps %3.2f Mpps\n"):format(tonumber(rx)/nanos * 8, rxp * 1000 / nanos))
end

