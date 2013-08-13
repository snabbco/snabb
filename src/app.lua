module(...,package.seeall)

--- # App runtime system

-- Dictionary of all instantiated apps (Name -> App).
all = {}

function new (class)
   app = { runnable = true }
   return setmetatable(app, {__index=class})
end

-- Take a breath. First "inhale" by pulling in packets from all
-- available sources. Then "exhale" by pushing the packets through
-- links until the stop.
function breathe ()
   -- Inhale
   print("inhale")
   for _, app in pairs(all) do
      if app.pull then app:pull() end
   end
   -- Exhale
   repeat
      local progress = false
      for _, app in pairs(all) do
	 if app.runnable and app.push then
	    app.runnable = false
	    app:push()
	    progress = true
	 end
      end
   until not progress
   -- (TODO) Timer-driven callbacks
   -- (TODO) Status reporting / counter collection
   -- (TODO) Restart crashed apps after delay
end

--- # Test apps

-- Source app: pull brings 10 packets onto each output port.
Source = {}
function Source:pull ()
   for _, o in pairs(self.output) do
      for i = 1, 10 do
	 link.transmit(o, packet.new())
      end
   end
end

-- Join app: push sends packets from all inputs onto 'output.link'.
Join = {}
function Join:push () 
   for _, inport in pairs(self.input) do
      while not link.empty(inport) do
	 link.transmit(self.output.link, link.receive(inport))
      end
   end
end

-- Split app: For each input port, push round-robbins packets onto each output.
Split = {}
function Split:push ()
   for _, i in pairs(self.input) do
      repeat
	 for _, o in pairs(self.output) do
	    if not link.empty(i) then
	       link.transmit(o, link.receive(i))
	    end
	 end
      until link.empty(i)
   end
end

-- Sink app: push receives and discards all packets from each input port.
Sink = {}
function Sink:push ()
   for _, i in pairs(self.input) do
      while not link.empty(i) do link.receive(i) end
   end
end

Buzz = {}
function Buzz:pull () print "bzzz pull" end
function Buzz:push () print "bzzz push" end

function selftest ()
   print("selftest: app")
   all["buzz"] = new(Buzz)
   breathe()
   print("selftest OK")
end

