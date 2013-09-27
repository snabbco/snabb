module(...,package.seeall)

local app = require("core.app")
local buffer = require("core.buffer")
local packet = require("core.packet")

--- # `Source` app: generate synthetic packets

Source = {}

function Source:new()
   return setmetatable({}, {__index=Source})
end

function Source:pull ()
   for _, o in ipairs(self.outputi) do
      for i = 1, 1000 do
         local p = packet.allocate()
         packet.add_iovec(p, buffer.allocate(), 60)
	 app.transfer(o, p)
      end
   end
end

--- # `Join` app: Merge multiple inputs onto one output

Join = {}

function Join:new()
   return setmetatable({}, {__index=Join})
end

function Join:push () 
   for _, inport in ipairs(self.inputi) do
      for _ = 1,math.min(app.nreadable(inport), app.nwritable(self.output.out)) do
	 app.transfer(self.output.out, app.receive(inport))
      end
   end
end

--- ### `Split` app: Split multiple inputs across multiple outputs

-- For each input port, push packets onto outputs. When one output
-- becomes full then continue with the next.
Split = {}

function Split:new ()
   return setmetatable({}, {__index=Split})
end

function Split:push ()
   for _, i in ipairs(self.inputi) do
      for _, o in ipairs(self.outputi) do
         for _ = 1, math.min(app.nreadable(i), app.nwritable(o)) do
            app.transfer(o, app.receive(i))
         end
      end
   end
end

--- ### `Sink` app: Receive and discard packets

Sink = {}

function Sink:new ()
   return setmetatable({}, {__index=Sink})
end

function Sink:push ()
   for _, i in ipairs(self.inputi) do
      for _ = 1, app.nreadable(i) do
	 local p = app.receive(i)
	 assert(p.refcount == 1)
	 packet.deref(p)
      end
   end
end

--- ### `Buzz` app: Print a debug message when called

Buzz = {}

function Buzz:new ()
   return setmetatable({}, {__index=Buzz})
end

function Buzz:pull () print "bzzz pull" end
function Buzz:push () print "bzzz push" end


