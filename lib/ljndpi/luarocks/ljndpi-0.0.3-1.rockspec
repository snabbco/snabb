package = "ljndpi"
version = "0.0.3-1"
source = {
   url = "git://github.com/aperezdc/ljndpi",
   tag = "v0.0.3"
}
description = {
   summary = "LuaJIT FFI binding for the nDPI deep packet inspection library",
   homepage = "https://github.com/aperezdc/ljndpi",
   license = "MIT/X11",
   maintainer = "Adrián Pérez de Castro <aperez@igalia.com>"
}
dependencies = {
   "lua >= 5.1"
}
build = {
   type = "builtin",
   modules = {
      ndpi = "ndpi.lua",
      ["ndpi.c"] = "ndpi/c.lua",
      ["ndpi.protocol_bitmask"] = "ndpi/protocol_bitmask.lua",
      ["ndpi.protocol_ids_1_7"] = "ndpi/protocol_ids_1_7.lua",
      ["ndpi.protocol_ids_1_8"] = "ndpi/protocol_ids_1_8.lua",
      ["ndpi.wrap"] = "ndpi/wrap.lua"
   }
}
