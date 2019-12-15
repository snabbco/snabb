-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Includes code ported from smoltcp
-- (https://github.com/m-labs/smoltcp), whose copyright is the
-- following:
---
-- Copyright (C) 2016 whitequark@whitequark.org
-- 
-- Permission to use, copy, modify, and/or distribute this software for
-- any purpose with or without fee is hereby granted.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
-- WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
-- MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
-- ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
-- WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
-- AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT
-- OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

module(...,package.seeall)

local ffi = require("ffi")

local NONE, IDLE, RETRANSMIT, CLOSE = 0, 1, 2, 3

timer_t = ffi.typeof[[
struct {
   uint8_t kind;
   uint64_t expires_at; /* for idle, retransmit, close */
   uint64_t delay; /* for retransmit */
} __attribute__((packed))
]]

local retransmit_delay = 100
local close_delay = 10000

local timer = {}
timer.__index = timer

function timer:should_keep_alive(ts)
   return self.kind == IDLE and self.expires_at <= ts
end

function timer:should_retransmit(ts)
   if self.kind == RETRANSMIT and self.expires_at <= ts then
      return ts - self.expires_at + self.delay
   end
end

function timer:should_close(ts)
   return self.kind == CLOSE and self.expires_at <= ts
end

function timer:poll_at()
   if self.kind ~= NONE then return self.expires_at end
end

function timer:set_none()
   self.kind = NONE
end

function timer:set_idle(t, keep_alive_at)
   self.kind = IDLE
   self.expires_at = keep_alive_at or -1ULL
end

function timer:rewind_keep_alive(t, keep_alive_at)
   if self.kind == IDLE then self.expires_at = keep_alive_at or -1ULL end
end

function timer:set_keep_alive(t)
   timer:rewind_keep_alive(t, 0)
end

function timer:set_retransmit(ts)
   if self.kind == NONE or self.kind == IDLE then
      self.kind = RETRANSMIT
      self.expires_at = ts + retransmit_delay
      self.delay = retransmit_delay
   elseif self.kind == RETRANSMIT and self.expires_at <= ts then
      self.expires_at = ts + retransmit_delay
      self.delay = self.delay * 2
   end
end

function timer:set_close(ts)
   self.kind = CLOSE
   self.expires_at = ts + close_delay
end

function timer:is_retransmit(t)
   return self.kind == RETRANSMIT
end

timer_t = ffi.metatype(timer_t, timer)

function selftest()
   print('selftest: lib.tcp.timer')
   local t = timer_t()
   assert(not t:should_retransmit(1000))
   t:set_retransmit(1000)
   assert(not t:should_retransmit(1000))
   assert(not t:should_retransmit(1050))
   assert(t:should_retransmit(1101) == 101)
   t:set_retransmit(1101)
   assert(not t:should_retransmit(1101))
   assert(not t:should_retransmit(1150))
   assert(not t:should_retransmit(1200))
   assert(t:should_retransmit(1301) == 300)
   t:set_idle(1301)
   assert(not t:should_retransmit(1350))
   print('selftest: ok')
end
