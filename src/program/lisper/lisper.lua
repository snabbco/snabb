module(..., package.seeall)

local lib = require("core.lib")
local usage = require("program.lisper.README_inc")
local unix = require("apps.socket.unix")
local raw = require("apps.socket.raw")
local lines = require("apps.lines")
local tap = require("apps.tap.tap")

CONTROL_SOCK = "/var/tmp/ctrl.socket"
PUNT_IF = "veth0"
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

local function parse_fib_line(s)
	local id, mac, ips = s:match"^%s*%[([^%]]+)%]%s*([^%s]+)%s+(.*)$"
	assert(id, "invalid FIB line: "..s)
	local t = {}
	for ip in ips:split"%s*,%s*" do
		t[#t+1] = ip
	end
	return id, mac, t
end

local fib = {} --{vlan_id = {mac = {dest_ip1, ...}}}

local function update_fib_line(self, s)
	local id, mac, ips = parse_fib_line(s)
	local vlan = fib[id]
	if not vlan then
		vlan = {}
		fib[id] = vlan
	end
	vlan[mac] = ips
	print('added ', id, mac, table.concat(ips, ', '))
end

local function dest_ips(id, mac)
	return fib[id] and fib[id][mac]
end

function run (args)

   --unix.selftest()
   --tap.selftest()
   --os.exit()

   local args = lib.dogetopt(args, opt, "hc:p:n:i:m:N:", long_opts)

   local c = config.new()

   config.app(c, "ctl_socket", unix.UnixSocket, {filename = CONTROL_SOCK, listen = true})
   config.app(c, "fib_lines", lines.Lines, {callback = update_fib_line})
	config.link(c, "ctl_socket.tx -> fib_lines.rx")
	config.app(c, "punt", raw.RawSocket, PUNT_IF)

   engine.configure(c)
   print("LISPER started.")
	print("  network interface : "..NET_IF)
	print("  punt interface    : "..PUNT_IF)
	print("  control socket    : "..CONTROL_SOCK)
	print("  local IP          : "..LOCAL_IP)
	print("  local MAC         : "..LOCAL_MAC)
	print("  next hop          : "..NEXT_HOP)
	engine.main({report = {showlinks=true}})

end
