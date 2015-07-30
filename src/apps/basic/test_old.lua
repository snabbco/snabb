module(..., package.seeall)

basic_apps = require ('apps.basic.basic_apps')

function selftest()
   local c = config.new()
   config.app(c, 'source', basic_apps.Source, {size=120})
   config.app(c, 'sink', basic_apps.Sink)
   config.link(c, 'source.output -> sink.input')
   engine.configure(c)

   engine.main{duration=1, report={showlinks=true}}
end
