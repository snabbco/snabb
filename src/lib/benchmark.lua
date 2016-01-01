module(..., package.seeall)

--[[
	Things that could be in the json blob
	-- cpuid
	-- git commit id
	-- packet size
	-- src pcap file
	-- pcap md5/sha1
	-- uname
	-- libc version
	-- description from benchmark definiton
	-- comments for benchmark run, eg 'measure impact of adding 1/10/40 counters to link structure'
]]

function runbenchmarks(module, bname)
	local vl = require(module)
	local basic = require("apps.basic.basic_apps")
	local counter = require("core.counter")
	local pcap = require("apps.pcap.pcap")
	local ffi = require("ffi")
	local C = ffi.C

	local rets = { }

	local blaster = function(self, name, pcapfile)
		config.app(self,  ("%s_pcap"):format(name), pcap.PcapReader, pcapfile)
		config.app(self, name, basic.Repeater)
		config.link(self, ("%s_pcap.output -> %s.input"):format(name,name))
	end
	local senv = {}
	local S = require("syscall")
	for k,v in pairs(S.environ()) do
		if k:match('^SNABB_') then 
			senv[k] = v
		end
	end
	if not bname then
		bname = "benchmark"
	end
	for i,v in pairs(vl) do
		if i:find( ("^%s"):format(bname) ) then
			engine.configure(config.new())
			local c = config.new()
			c.dur = 5
			c.src = blaster
			c.busywait = false
			c.Hz = false
			config.app(c, "sink", basic.Sink)
			c = v(c)
			engine.configure(c)
			engine.busywait = c.busywait
			engine.Hz = c.Hz
			local start = C.get_monotonic_time()
			engine.main({ duration = c.dur, no_report = true })
			local finish = C.get_monotonic_time()
			stats = {}
			for i,v in pairs(engine.link_table) do
				local l = i:match('-> sink%.(.*)')
				if l then
					stats[l] = {}
					stats[l].packets = tonumber(counter.read(v.stats.rxpackets))
					stats[l].bytes = tonumber(counter.read(v.stats.rxbytes))
				end
			end
			table.insert(rets, {
				duration = {
					requested = c.dur,
					actual = finish - start
				},
				busywait = c.busywait,
				hz = c.Hz,
				module = module,
				test = i,
				links = stats,
				env = senv,
				hostname = S.gethostname(),
				date = os.date("!%Y-%m-%dT%TZ")
			})
		end
	end
	return rets
end