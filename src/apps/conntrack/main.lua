local app = require("core.app")
local config = require("core.config")
local pcap = require("apps.pcap.pcap")
local link = require("core.link")
local packet = require("core.packet")
local conntrack = require("apps.conntrack.conntrack")

local output_file = "/tmp/output.pcap"

local c = config.new()
config.app(c, "capture", pcap.PcapReader, "apps/conntrack/input.pcap")
config.app(c, "conntrack_app", conntrack.Conntrack)
config.app(c, "output_file", pcap.PcapWriter, output_file)

config.link(c, "capture.output -> conntrack_app.input")
config.link(c, "conntrack_app.output -> output_file.input")

print(("Results written at: %s"):format(output_file))

app.configure(c)
app.main({duration=1})
