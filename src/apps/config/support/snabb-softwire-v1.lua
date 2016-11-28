-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)
local app = require('core.app')

local function compute_config_actions(old_graph, new_graph, verb, path, arg)
   return app.compute_config_actions(old_graph, new_graph)
end

function get_config_support()
   return { compute_config_actions = compute_config_actions }
end
