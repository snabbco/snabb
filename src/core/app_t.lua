local config = require("core.config")
local app = require("core.app")

_NAME = 'test app'

return {
   app_config = function ()
      print("selftest: app")
      local App = {}
      function App:new () return setmetatable({}, {__index = App}) end
      local c1 = config.new()
      config.app(c1, "app1", App)
      config.app(c1, "app2", App)
      config.link(c1, "app1.x -> app2.x")
      print("empty -> c1")
      app.configure(c1)
      assert(#app.app_array == 2)
      assert(#app.link_array == 1)
      assert(app.app_table.app1 and app.app_table.app2)
      local orig_app1 = app.app_table.app1
      local orig_app2 = app.app_table.app2
      local orig_link = app.link_array[1]
      print("c1 -> c1")
      app.configure(c1)
      assert(app.app_table.app1 == orig_app1)
      assert(app.app_table.app2 == orig_app2)
      local c2 = config.new()
      config.app(c2, "app1", App, "config")
      config.app(c2, "app2", App)
      config.link(c2, "app1.x -> app2.x")
      config.link(c2, "app2.x -> app1.x")
      print("c1 -> c2")
      app.configure(c2)
      assert(#app.app_array == 2)
      assert(#app.link_array == 2)
      assert(app.app_table.app1 ~= orig_app1) -- should be restarted
      assert(app.app_table.app2 == orig_app2) -- should be the same
      -- tostring() because == does not work on FFI structs?
      assert(tostring(orig_link) == tostring(app.link_table['app1.x -> app2.x']))
      print("c2 -> c1")
      app.configure(c1) -- c2 -> c1
      assert(app.app_table.app1 ~= orig_app1) -- should be restarted
      assert(app.app_table.app2 == orig_app2) -- should be the same
      assert(#app.app_array == 2)
      assert(#app.link_array == 1)
      print("c1 -> empty")
      app.configure(config.new())
      assert(#app.app_array == 0)
      assert(#app.link_array == 0)
      print("OK")
   end,
}