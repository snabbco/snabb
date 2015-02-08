#!./snabb 

local app = require("core.app")
local config = require("core.config")
local pcap = require("apps.pcap.pcap")
local link = require("core.link")
local packet = require("core.packet")
local sprayer = require("apps.sprayer.sprayer")

local c = config.new()
config.app(c, "capture", pcap.PcapReader, "apps/sprayer/input.pcap")
config.app(c, "spray_app", sprayer.Sprayer)
config.app(c, "output_file", pcap.PcapWriter, "/tmp/output.pcap")

config.link(c, "capture.output -> spray_app.input")
config.link(c, "spray_app.output -> output_file.input")

app.configure(c)
app.main({duration=1})

