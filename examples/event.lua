-- example of event ioctls

local S = require "syscall"

local EV = S.c.EV
local MSC = S.c.MSC
local KEY = S.c.KEY
local ioctl = S.c.IOCTL
local t = S.types.t
local s = S.types.s

local kl = {}
for k, v in pairs(KEY) do kl[v] = k end

local oldassert = assert
local function assert(cond, s)
  collectgarbage("collect") -- force gc, to test for bugs
  return oldassert(cond, tostring(s)) -- annoyingly, assert does not call tostring!
end

local function ev(dev)
  if not dev then dev = "/dev/input/event0" end
  local fd = assert(S.open(dev, "rdonly"))

  local pversion = t.int1()

  assert(S.ioctl(fd, "EVIOCGVERSION", pversion))

  local version = pversion[0]

  print(string.format("evdev driver version: %d.%d.%d",
    bit.rshift(version, 16), 
    bit.band(bit.rshift(version, 8), 0xff),
    bit.band(version, 0xff)))

  local ev = S.t.input_event()
  while true do
    local ok = assert(fd:read(ev, s.input_event))

    if ev.type == EV.MSC then
      if ev.code == MSC.SCAN then
        print("MSC_SCAN: ", string.format("0x%x", ev.value));
      else
        print("MSC: ", ev.code, ev.value);
      end
    elseif ev.type == EV.KEY then
      if ev.value == 1 then print("down", kl[ev.code], ev.code)
      elseif ev.value == 0 then print("up", kl[ev.code], ev.code)
      elseif ev.value == 2 then print("repeat", kl[ev.code], ev.code)
      end
    else
      --print("EVENT TYPE: ", ev.type, "CODE:", ev.code, "VALUE: ", string.format("0x%x", ev.value));
    end
  end
end



ev(arg[1])

