----------------------------------------------------------------------------
-- LuaJIT trace profiler module.
--
-- Copyright (C) 2005-2011 Mike Pall. All rights reserved.
-- Released under the MIT/X license. See Copyright Notice in luajit.h
----------------------------------------------------------------------------
-- NYI: add description
------------------------------------------------------------------------------

-- Cache some library functions and objects.
local jit = require("jit")
assert(jit.version_num == 20002, "LuaJIT core/library version mismatch")
local jutil = require("jit.util")
local funcinfo = jutil.funcinfo
local sub, format = string.sub, string.format
local stdout, stderr = io.stdout, io.stderr

-- Active flag and output file handle.
local active, out

------------------------------------------------------------------------------

local tprof_ud, vmprof, vmp, traces, tinfo

local function tprof_trace(what, tr, func, pc, otr, oex)
  if what == "start" then
    local fi = funcinfo(func, pc)
    local oi = otr and format("(%d/%d)", otr, oex) or ""
    tinfo = format("%-7s %s", oi, fi.loc)
  elseif what == "stop" then
    traces[tr] = tinfo
  elseif what == "flush" then
    out:write("WARNING -- trace flushed\n")
  end
end

local vmstates = {
  "assembler", "optimizer", "recorder", "exit handling", "GC",
  "C functions", "interpreter",
}

local function invcomp(a, b)
  return a > b
end

local function tprof_finish()
  local vmp = vmp
  local samples = vmprof.tstop(vmp)
  local isamp = 100/samples
  local cutoff = samples/1000 -- 0.1%
  local tcount = vmprof.tcount
  local tc, n = {}, 0
  for i=1,4095 do
    if not traces[i] then break end
    local c = tcount(vmp, i)
    if c > cutoff then
      n = n + 1
      tc[n] = format("%5.1f %3d %s\n", c*isamp, i, traces[i])
    end
  end
  for i=1,7 do
    local c = tcount(vmp, i-8)
    if c > cutoff then
      n = n + 1
      tc[n] = format("%5.1f %s\n", c*isamp, vmstates[i])
    end
  end
  table.sort(tc, invcomp)
  if n > 15 then n = 15 end
  for i=1,n do out:write(tc[i]) end
end

------------------------------------------------------------------------------

-- Detach dump handlers.
local function tprofoff()
  if active then
    active = false
    jit.attach(tprof_trace)
    tprof_finish()
    if out and out ~= stdout and out ~= stderr then out:close() end
    out = nil
    traces = nil
  end
end

-- Open the output file and attach dump handlers.
local function tprofon(outfile)
  if active then tprofoff() end

  vmprof = require("jit.vmprof")

  traces = {}
  jit.attach(tprof_trace, "trace")

  if not outfile then outfile = os.getenv("LUAJIT_TPROFFILE") end
  if outfile then
    out = outfile == "-" and stdout or assert(io.open(outfile, "w"))
  else
    out = stderr
  end

  vmp = vmprof.tstart(20)
  tprof_ud = newproxy(true)
  getmetatable(tprof_ud).__gc = tprof_finish

  active = true
end

-- Public module functions.
module(...)

on = tprofon
off = tprofoff
start = tprofon -- For -j command line option.

