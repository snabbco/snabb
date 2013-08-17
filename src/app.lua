module(...,package.seeall)

local link = require("link")

--- # App runtime system

-- Dictionary of all instantiated apps (Name -> App).
apps = {}
links = {}

function new (class)
   app = { runnable = true, input = {}, output = {} }
   return setmetatable(app, {__index=class})
end

function connect (from_app, from_port, to_app, to_port)
   local name = from_app.."."..from_port.."->"..to_app.."."..to_port
   local l = {link = link.new(), to_app = apps[to_app] }
   links[name] = l
   apps[from_app].output[from_port] = l
   apps[to_app].input[to_port] = l
end

-- Take a breath. First "inhale" by pulling in packets from all
-- available sources. Then "exhale" by pushing the packets through
-- links until the stop.
function breathe ()
   -- Inhale
   for _, app in pairs(apps) do
      if app.pull then app:pull() end
   end
   -- Exhale
   repeat
      local progress = false
      for _, app in pairs(apps) do
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

function report ()
   print("report")
   for name, l in pairs(links) do
      print(name, tonumber(l.link.ring.stats.tx) .. " packet(s) transmitted")
   end
end

--- # Test apps

function transmit (l, p)
   l.to_app.runnable = true
   link.transmit(l.link, p)
end

function receive (l)
   return link.receive(l.link)
end

function empty (l)
   return link.empty(l.link)
end

function size2 (l)
   return link.size2(l.link)
end

-- Source app: pull brings 10 packets onto each output port.
Source = {}
function Source:pull ()
   for _, o in pairs(self.output) do
      for i = 1, 1000 do
	 transmit(o, packet.allocate())
      end
   end
end

-- Join app: push sends packets from all inputs onto 'output.link'.
Join = {}
function Join:push () 
   for _, inport in pairs(self.input) do
      while not empty(inport) do
	 transmit(self.output.out, receive(inport))
      end
   end
end

-- Split app: For each input port, push round-robbins packets onto each output.
Split = {}
function Split:push ()
   for _, i in pairs(self.input) do
      repeat
	 for _, o in pairs(self.output) do
	    if not empty(i) then
	       transmit(o, receive(i))
	    end
	 end
      until empty(i)
   end
end

-- Sink app: push receives and discards all packets from each input port.
Sink = {}
function Sink:push ()
   for _, i in pairs(self.input) do
      while not empty(i) do receive(i) end
   end
end

Buzz = {}
function Buzz:pull () print "bzzz pull" end
function Buzz:push () print "bzzz push" end

function selftest ()
   print("selftest: app")
   -- Setup this test topology:
   --
   --              .--------.
   --              v        |
   -- source --> join --> split --> sink
   -- 
   -- FIXME: Strictly this is non-terminating, as one packet could get
   -- stuck looping split->join->split endlessly. For now I depend on
   -- this accidentally deterministically not happening.
   apps["source"] = new(Source)
   apps["join"] = new(Join)
   apps["split"] = new(Split)
   apps["sink"] = new(Sink)
   connect("source", "out", "join", "in1")
   connect("join",   "out", "split", "in")
   connect("split", "out2", "sink", "in")
   connect("split", "out1", "join", "in2")
   breathe()
   report()
   print("selftest OK")
end

