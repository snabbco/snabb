#!/usr/bin/env snabb

local app = require("core.app")
local config = require("core.config")
local pcap = require("apps.pcap.pcap")
local link = require("core.link")
local raw = require("apps.socket.raw")

local c = config.new()
config.app(c, "capture", pcap.PcapReader, "input.pcap")
config.app(c, "sprayer", raw.RawSocket, "veth0")

config.link(c, "capture.output -> sprayer.rx")

app.configure(c)
app.main({duration=1})
