module(..., package.seeall)

function selftest()
   local c = config.new()
   config.app(c, 'source', 'apps.basic.source', {size=120})
   config.app(c, 'sink', 'apps.basic.sink')
   config.link(c, 'source.output -> sink.input')
   engine.configure(c)

   engine.main{duration=0.1, report={showlinks=true}}
   engine.closeapps()
end
