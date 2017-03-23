package = "ljndpi"
version = "scm-1"
source = {
   url = "git://github.com/aperezdc/ljndpi"
}
description = {
   maintainer = "Adrián Pérez de Castro <aperez@igalia.com>",
   summary = "LuaJIT FFI binding for the nDPI deep packet inspection library",
   homepage = "https://github.com/aperezdc/ljndpi",
   license = "MIT/X11",
}
dependencies = {
   "lua >= 5.1"
}
build = {
   type = "builtin",
   modules = {
      ["ndpi"]                  = "ndpi.lua",
      ["ndpi.c"]                = "ndpi/c.lua",
      ["ndpi.wrap"]             = "ndpi/wrap.lua",
      ["ndpi.protocol_bitmask"] = "ndpi/protocol_bitmask.lua",
      ["ndpi.protocol_ids_1_7"] = "ndpi/protocol_ids_1_7.lua",
      ["ndpi.protocol_ids_1_8"] = "ndpi/protocol_ids_1_8.lua",
   }
}
