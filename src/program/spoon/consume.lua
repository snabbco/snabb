
local S = require('syscall')
S.sched_setaffinity(nil, {13})
engine.busywait=true

local basic_apps = require('apps.basic.basic_apps')
local inter_proc = require('apps.inter_proc.app')


local c = config.new()
config.app(c, 'receive', inter_proc.Receive, {linkname='spoon_link'})
config.app(c, 'sink', basic_apps.Sink)
config.link(c, 'receive.output -> sink.input')
engine.configure(c)

engine.main{duration=1, report={showlinks=true, showapps=true}}
