module(...,package.seeall)

--802.1Q trunk app

local app = require("core.app")
local lib = require("core.lib")
local packet = require("core.packet")
local link = require("core.link")
local ffi = require("ffi")

local ct = ffi.typeof[[
	struct {
		char     dmac[6];
		char     smac[6];
		uint16_t tpid; // 81:00 = 802.1q
		struct {
			uint16_t pcp: 3;
			uint16_t dei: 1;
			uint16_t vid: 12;
		} tci;
	} __attribute__((packed))
]]
local ct_size = ffi.sizeof(ct)
local ctp = ffi.typeof("$*", ct)

Trunk = {}

function Trunk:new(t)
   return setmetatable({ports = t}, {__index = self})
end

function Trunk:push()
	--untag frames from input "trunk" port to output vlan ports
	local rx = self.input.trunk
   if rx then
		while not link.empty(rx) do
			local p = link.peek(rx)
			local h = ffi.cast(ctp, p.data)
			if p.length >= ct_size then
				if h.tpid == 0x81 then --802.1Q frame
					local vlan_id = lib.ntohs(h.vid)
					local port = self.ports[vlan_id]
					if port then
						local tx = self.output[port]
						if tx then
							if link.full(tx) then
								goto abort --abort without pulling the packet
							else
								local dp = packet.allocate()
								dp.length = p.length - 4
								ffi.copy(dp.data, p.data, 12)
								ffi.copy(dp.data + 12, p.data + 16, p.length - 16)
								link.transmit(tx, dp)
							end
						end
					end
				end
			end
			packet.free(link.receive(rx))
		end
	end
	::abort::
	--tag frames from input vlan ports to output "trunk" port
	local tx = self.output.trunk
	if tx then
		for vlan_id, rxname in pairs(self.ports) do
			local rx = self.input[rxname]
			if rx then
				while not link.empty(rx) and not link.full(tx) do --TODO: round-robin
					local p = link.receive(rx)
					local dp = packet.allocate()
					dp.length = p.length + 4
					ffi.copy(dp.data, p.data, 12)
					ffi.copy(dp.data + 16, p.data + 12, p.length - 12)
					dh = ffi.cast(ctp, dp.data)
					dh.tpid = 0x81
					dh.tci.pcp = 0
					dh.tci.dei = 0
					dh.tci.vid = lib.htons(vlan_id)
					link.transmit(tx, dp)
					packet.free(p)
				end
			end
		end
	end
end
