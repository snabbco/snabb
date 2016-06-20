local linkname = main.parameters[1]
local core = tonumber(main.parameters[2])

local S = require('syscall')
S.sched_setaffinity(nil, {core})
engine.busywait=true

local basic_apps = require('apps.basic.basic_apps')
local transmit = require('apps.inter_proc.transmit')


local c = config.new()
config.app(c, 'source', basic_apps.Source, {size=120})
config.app(c, 'transmit', transmit, {linkname='spoon_'..linkname})
config.link(c, 'source.output -> transmit.input')
engine.configure(c)

engine.main{done=function() return false end, report={showlinks=true, showapps=true}}
