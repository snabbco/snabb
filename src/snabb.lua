-- snabb.lua: Snabb Switch core API

-- This module provides the complete Snabb Switch API.
--
-- Consolidating the whole API into a module has these benefits:
--
-- * Single source for reference, making updates, checking for changes.
-- * Multiple API versions could co-exist (e.g. snabb, snabb2, snabb3).
-- * Gives control over when/how changes are exposed to users.

-- The API is defined by the items in this table.
local snabb = { api_verison = '1.0' }

local engine = require("core.app")
local packet = require("core.packet")
local link   = require("core.link")
local config = require("core.config")

--------------------------------------------------------------
-- Engine API
--------------------------------------------------------------

snabb.engine = {}

-- snabb.engine.run()
snabb.engine.run = engine.run

--------------------------------------------------------------
-- Packet API
--------------------------------------------------------------

-- snabb.packet() => packet
--   Return a new empty packet object.
function snabb.packet ()
   return packet.allocate()
end

-- Methods for packet objects:

local packetmethods = {

   -- packet:length() = number
   --   Return the packet data length.
   length = packet.length,

   -- packet:clone() => packet
   --   Return a new copy of the packet.
   clone = packet.clone,

   -- packet:append(pointer, length)
   --   Append the LEGNTH bytes at POINTER to the end the packet.
   append = packet.append,

   -- packet:prepend(pointer, length)
   --   Prepend the LENGTH bytes at POINTER to the start of the packet.
   prepend = packet.prepend,

   -- packet:shiftleft(bytes)
   --   Move the packet data to the left by BYTES.
   shiftleft = packet.shiftleft,
}

-- Make the packet methods available on 'struct packet' objects
ffi.metatable('struct packet', {__index = packetmethods})

--------------------------------------------------------------
-- Config API
--------------------------------------------------------------

local configmethods

-- snabb.config()
--   Return a new empty config object.
function snabb.config ()
   return setmetatable(config.new(), {__index = configmethods})
end

configmethods = {

   -- config:set_app(name, class, config)
   --   Define a new app in the config. If an app called NAME already
   --   exists then it is replaced.
   set_app = config.app,

   -- config:set_link(spec)
   --   Define a unidirectional link between named ports of apps.
   --
   --   SPEC is a string with the format is APP1.PORT1->APP2.PORT2.
   --   For example, "filter.input->filter.output".
   --
   --   The named apps must already exist and have the required ports.
   --   If either of the ports is already connected with a link then
   --   that is replaced by the new link. (Each port can be connected
   --   only once.)
   set_link = config.link,

   -- ...
}

--------------------------------------------------------------
-- Link API
--------------------------------------------------------------

-- ...

return snabb

