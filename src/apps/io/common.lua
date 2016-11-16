-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- config.app(c, "IO", IO, {type="pci", device="01:00.0",
--                          queues={a = {...}, ...}})

module(..., package.seeall)

local types = {}
function register (type, app)
   assert(app, "Must supply app")
   assert(not types[type], "Duplicate IO type: "..type)
   types[type] = app
   return app
end

IO = {
   config = {
      type = {default='emu'},
      device = {},
      queues = {required=true}
   }
}

function IO:configure (c, name, conf)
   local app = assert(types[conf.type], "Unknown IO type: "..conf.type)
   config.app(c, name, app, {device=conf.device, queues=conf.queues})
end

function selftest ()
   require("apps.io.emu")
   local c = config.new()
   config.app(c, "IO", IO,
              {queues = {a = {macaddr="60:50:40:40:20:10", hash=1},
                         b = {macaddr="60:50:40:40:20:10", hash=2}}})
   engine.configure(c)
   engine.report_apps()
   engine.report_links()
end
