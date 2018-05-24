-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Epoll wrapper.

module(..., package.seeall)

local bit = require('bit')
local S = require('syscall')

local Epoll = {}

local INITIAL_MAXEVENTS = 8

function new()
   local ret = { fd = assert(S.epoll_create()),
                 active_events = {},
                 events = S.t.epoll_events(INITIAL_MAXEVENTS),
                 event = S.t.epoll_event() }
   return setmetatable(ret, { __index = Epoll })
end

RD = S.c.EPOLL.IN + S.c.EPOLL.RDHUP
WR = S.c.EPOLL.OUT
RDWR = RD + WR
ERR = S.c.EPOLL.ERR + S.c.EPOLL.HUP

function Epoll:add(s, events)
   local fd = type(s) == 'number' and s or s:getfd()
   local active = self.active_events[fd] or 0
   local event = self.event
   event.events = bit.bor(events, active, S.c.EPOLL.ONESHOT)
   event.data.fd = fd
   if active ~= event.events then
      local ok, err = self.fd:epoll_ctl("mod", fd, event)
      if not ok then assert(self.fd:epoll_ctl("add", fd, event)) end
   end
end

function Epoll:poll(timeout)
   -- Returns iterator.
   local reviter, events, count = self.fd:epoll_wait(self.events, timeout or 0)
   if not reviter then
      local err = events
      if err.INTR then return function() end, nil, nil end
      error(err)
   end
   -- Since we add fd's with EPOLL_ONESHOT, now that the event has
   -- fired, the fd is now deactivated.  Record that fact.
   for i=0, count-1 do self.active_events[events[i].data.fd] = 0 end
   if count == #self.events then
      -- If we received `maxevents' events, it means that probably there
      -- are more active fd's in the queue that we were unable to
      -- receive.  Expand our event buffer in that case.
      self.events = S.t.epoll_events(#self.events * 2)
   end
   return reviter, events, count
end

function Epoll:close()
   self.fd:close()
   self.fd = nil
end

function selftest()
   print('selftest: lib.fibers.epoll')
   local lib = require('core.lib')
   local epoll = new()
   local function poll(timeout)
      local events = {}
      for _, event in epoll:poll(timeout) do
         table.insert(events, {fd=event.data.fd, events=event.events})
      end
      return events
   end
   assert(lib.equal(poll(), {}))
   local ok, err, rd, wr = S.pipe()
   assert(ok, err)
   for i = 1,10 do
      epoll:add(rd, RD)
      epoll:add(wr, WR)
      assert(lib.equal(poll(), {{fd=wr:getfd(), events=WR}}))
      assert(wr:write("foo") == 3)
      -- The write end isn't active because we haven't re-added it to the
      -- epoll set.
      assert(lib.equal(poll(), {{fd=rd:getfd(), events=S.c.EPOLL.IN}}))
      -- Now nothing is active, so no events even though both sides can
      -- do I/O.
      assert(lib.equal(poll(), {}))
      epoll:add(rd, RD)
      epoll:add(wr, WR)
      -- Having re-added them though they are indeed active.
      assert(#poll() == 2)
      assert(rd:read() == "foo")
   end
   print('selftest: ok')
end
