-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local lib = require("core.lib")
local tsc = require("lib.tsc")
local ffi = require("ffi")

local token_bucket = {}
local params = {
   rate = { required = true },
   burst_size = { required = false },
}

function new (arg)
   local config = lib.parse(arg, params)
   local tb = setmetatable({}, { __index = token_bucket })

   tb._tsc = tsc.new()
   tb._time_fn = tb._tsc:time_fn()
   -- Use explicit box to avoid garbage in can_take()
   tb._tstamp = ffi.new("uint64_t [1]")
   tb:set(config.rate, config.burst_size)

   return tb
end

function token_bucket:set (rate, burst_size)
   if rate ~= nil then
      assert(type(rate) == 'number')
      assert(rate > 0)
      self._rate = rate
      -- Ticks per token
      self._tpt = tonumber(self._tsc:tps())/rate + 0ULL
   end

   if burst_size == nil then
      burst_size = self._rate
   end
   assert(type(burst_size) == 'number')
   self._burst_size = math.ceil(burst_size)

   self._tokens = self._burst_size
   self._tstamp[0] = self._time_fn()
end

function token_bucket:get ()
   return self._rate, self._burst_size
end

function token_bucket:can_take (n)
   local n = n or 1
   local tokens = self._tokens
   if n <= tokens then
      return true
   else
      -- Accumulate fresh tokens since the last time we've checked
      local elapsed = self._time_fn() - self._tstamp[0]
      if elapsed >= self._tpt then
         -- We have at least one new token.  We're careful to use
         -- uint64 values to make this an integer division. Would be
         -- nice if we had access to the remainder from the `div`
         -- instruction.
         local fresh_tokens = elapsed/self._tpt
         tokens = tokens + tonumber(fresh_tokens)
         self._tstamp[0] = self._tstamp[0] + self._tpt * fresh_tokens
         if tokens > self._burst_size then
            tokens = self._burst_size
         end
         self._tokens = tokens
         return n <= tokens
      end
      return false
   end
end

function token_bucket:take (n)
   local n = n or 1
   if self:can_take(n) then
      self._tokens = self._tokens - n
      return true
   end
   return false
end

function token_bucket:take_burst ()
   self:can_take(self._burst_size)
   local tokens = self._tokens
   self._tokens = 0
   return tokens
end

function selftest()
   local rate, burst_size = 10000, 50
   local tb = new({ rate = rate, burst_size = burst_size })
   local interval = 0.5 -- seconds
   local i = 0
   local now = ffi.C.get_time_ns()
   while ffi.C.get_time_ns() - now < interval * 1000000000 do
      if tb:take() then
         i = i + 1
      end
   end
   local rate_eff = (i - burst_size)/interval
   assert(rate_eff/rate == 1)

   local r, b = tb:get()
   assert(r == rate)
   assert(b == burst_size)

   tb:set(rate, burst_size)
   assert(tb:can_take(burst_size))
   assert(not tb:can_take(burst_size + 1))
   assert(tb:take(burst_size))
   assert(not tb:take())

   tb:set(0.1)
   local r, b = tb:get()
   assert(r == 0.1)
   assert(b == 1)
end
