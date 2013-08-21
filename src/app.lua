module(...,package.seeall)

local link_ring = require("link_ring")
require("packet_h")

--- # App runtime system

-- Dictionary of all instantiated apps (Name -> App).
apps = {}
appsi = {}
links = {}

function new (class)
   app = { runnable = true,
	   input = {}, output = {},
	   inputi = {}, outputi = {}
	}
   return setmetatable(app, {__index=class})
end

function connect (from_app, from_port, to_app, to_port)
   local name = from_app.."."..from_port.."->"..to_app.."."..to_port
   l = new_link(apps[to_app])
   links[name] = l
   apps[from_app].output[from_port] = l
   table.insert(apps[from_app].outputi, l)
   apps[to_app].input[to_port] = l
   table.insert(apps[to_app].inputi, l)
end

function new_link (to_app)
   return { ring = link_ring.new(), to_app = to_app }
end

-- Take a breath. First "inhale" by pulling in packets from all
-- available sources. Then "exhale" by pushing the packets through
-- links until the stop.
function breathe ()
   -- Inhale
   for _, app in ipairs(appsi) do
      if app.pull then app:pull() end
   end
   -- Exhale
   repeat
      local progress = false
      for _, app in ipairs(appsi) do
	 if app.runnable and app.push then
	    app.runnable = false
	    app:push()
	    progress = true
	    -- Free packets
	    --[[
	    for an,app in pairs(apps) do
	       for inn,i in pairs(app.input) do
		  link_ring.cleanup_after_receive(i.ring)
	       end
	    end
	    --]]
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
      print(name, lib.comma_value(tostring(tonumber(l.ring.stats.tx))) .. " packet(s) transmitted")
   end
end

local link_ring_transmit = link_ring.transmit
local function transmit (l, p)
   l.to_app.runnable = true
   link_ring_transmit(l.ring, p)
end

local packet_deref = packet.deref
local function transfer (l, p)
   transmit(l, p)
   packet_deref(p)
end

local link_ring_receive = link_ring.receive
local function receive (l)
   return link_ring_receive(l.ring)
end

local link_ring_empty = link_ring.empty
local function empty (l)
   return link_ring_empty(l.ring)
end

--- # Test apps

-- Source app: pull brings 10 packets onto each output port.
Source = {}
function Source:pull ()
   local o = self.output.out
   for _, o in ipairs(self.outputi) do
      for i = 1, 100 do
	 local p = packet.allocate()
	 transfer(o, p)
      end
   end
end

-- Join app: push sends packets from all inputs onto 'output.link'.
Join = {}
function Join:push () 
   for _, inport in ipairs(self.inputi) do
      while not empty(inport) do
	 transfer(self.output.out, receive(inport))
      end
   end
end

-- Split app: For each input port, push round-robbins packets onto each output.
Split = {}
function Split:push ()
   for _, i in ipairs(self.inputi) do
      repeat
	 for _, o in ipairs(self.outputi) do
	    if not empty(i) then
	       transfer(o, receive(i))
	    end
	 end
      until empty(i)
   end
end

-- Sink app: push receives and discards all packets from each input port.
Sink = {}
function Sink:push ()
   for _, i in ipairs(self.inputi) do
      while not empty(i) do
	 local p = receive(i)
	 assert(p.refcount == 1)
	 packet.deref(p)
      end
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
   table.insert(appsi, apps.source)
   table.insert(appsi, apps.join)
   table.insert(appsi, apps.split)
   table.insert(appsi, apps.sink)
   connect("source", "out", "join", "in1")
   connect("join",   "out", "split", "in")
   connect("split", "out2", "sink", "in")
   connect("split", "out1", "join", "in2")
   local deadline = lib.timer(10e9)
   repeat breathe() until deadline()
   print("zoom")
   report()
   print("selftest OK")
end

