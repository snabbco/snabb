module(..., package.seeall)

local ffi = require('ffi')

lwaftr_message_t = ffi.typeof('struct { uint8_t kind; }')
lwaftr_message_reload = 1
lwaftr_message_dump_config = 2
