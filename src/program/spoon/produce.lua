
local S = require('syscall')
S.sched_setaffinity(nil, {12})
engine.busywait=true

local basic_apps = require('apps.basic.basic_apps')
local inter_proc = require('apps.inter_proc.app')


local c = config.new()
config.app(c, 'source', basic_apps.Source, {size=120})
config.app(c, 'transmit', inter_proc.Transmit, {linkname='spoon_link'})
config.link(c, 'source.output -> transmit.input')
engine.configure(c)

engine.main{done=function() return false end, report={showlinks=true, showapps=true}}
