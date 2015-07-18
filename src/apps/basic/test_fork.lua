module(..., package.seeall)

basic_apps = require ('apps.basic.basic_apps')

function selftest()
   local c = config.new()
   config.cpu(c, 'proc1')
   config.cpu(c, 'proc2')
   config.app(c, 'source', basic_apps.Source, {size=120, cpu='proc1'})
   config.app(c, 'sink', basic_apps.Sink, {cpu='proc2'})
   config.link(c, 'source.output -> sink.input')
   engine.configure(c)

   engine.main{duration=10, report={showlinks=true, showapps=true, showaccum=true}}
end
