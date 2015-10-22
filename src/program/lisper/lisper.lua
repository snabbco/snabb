module(..., package.seeall)

local lib = require("core.lib")
local raw = require("apps.socket.raw")
local usage = require("program.lisper.README_inc")

CONTROL_SOCK = 'ctrl.socket'
PUNT_IF = 'veth0'
NET_IF = "01:00.0"
LOCAL_IP = ""
LOCAL_MAC = ""
NEXT_HOP = ""

local long_opts = {
   control = "c",
   ["punt-interface"] = "p",
   ["network-device"] = "n",
   ["local-ip"] = "i",
   ["local-mac"] = "m",
   ["next-hop"] = "N",
   help = "h",
}
local opt = {}
function opt.h (arg) print(usage) main.exit(0) end
function opt.c (arg) CONTROL_SOCK = arg end
function opt.p (arg) PUNT_IF = arg end
function opt.n (arg) NET_IF = arg end
function opt.i (arg) LOCAL_IP = arg end
function opt.m (arg) LOCAL_MAC = arg end
function opt.N (arg) NEXT_HOP = arg end

local UnixSocket = {}

function UnixSocket:new()

end


function run (args)

   print'hello3'
   local args = lib.dogetopt(args, opt, "hc:p:n:i:m:N:", long_opts)

   local c = config.new()
   --[[
   config.app(c, "ctl", raw.RawSocket, PUNT_IF)
   config.app(c, "punt", raw.RawSocket, PUNT_IF)
   config.link(c, "capture.output -> playback.rx")
   ]]

   engine.configure(c)
   engine.main({duration=1, report = {showlinks=true}})

end
