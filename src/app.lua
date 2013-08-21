module(...,package.seeall)

local link_ring = require("link_ring")
require("packet_h")

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
   l = new_link(apps[to_app])
   links[name] = l
   apps[from_app].output[from_port] = l
   apps[to_app].input[to_port] = l
end

function new_link (to_app)
   return { ring = link_ring.new(), to_app = to_app }
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
   -- Free packets
   for _,app in pairs(apps) do
      for _,i in pairs(app.input) do
	 link_ring.cleanup_after_receive(i)
      end
   end
   -- (TODO) Timer-driven callbacks
   -- (TODO) Status reporting / counter collection
   -- (TODO) Restart crashed apps after delay
end

function report ()
   print("report")
   for name, l in pairs(links) do
      print(name, lib.comma_value(tostring(tonumber(l.ring.stats.tx))) .. " packet(s) transmitted")
   end
end

function transmit (l, p)
   l.to_app.runnable = true
   link_ring.transmit(l.ring, p)
end

function receive (l)
   return link_ring.receive(l.ring)
end

function empty (l)
   return link_ring.empty(l.ring)
end

--- # Test apps

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
   local deadline = lib.timer(1e9)
   repeat breathe() until deadline()
   report()
   print("selftest OK")
end

