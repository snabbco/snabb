#! /usr/bin/env lua
--
-- wrap.lua
-- Copyright (C) 2016 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local lib = require("ndpi.c")
local ffi = require("ffi")
local C   = ffi.C

---------------------------------------------------------- Identifier ------

local id_struct_ptr_t = ffi.typeof("ndpi_id_t*")
local id_struct_size  = lib.ndpi_detection_get_sizeof_ndpi_id_struct()

local function id_new(ctype)
   local id = ffi.cast(id_struct_ptr_t, ffi.gc(C.malloc(id_struct_size), id_free))
   ffi.fill(id, id_struct_size)
   return id
end

local id_type = ffi.metatype("ndpi_id_t", {
   __new = id_new;
   __gc  = C.free;
})

---------------------------------------------------------------- Flow ------

local flow_struct_ptr_t = ffi.typeof("ndpi_flow_t*")
local flow_struct_size  = lib.ndpi_detection_get_sizeof_ndpi_flow_struct()

local function flow_new(ctype)
   local flow = ffi.cast(flow_struct_ptr_t, ffi.gc(C.malloc(flow_struct_size), flow_free))
   ffi.fill(flow, flow_struct_size)
   return flow
end

local flow_type = ffi.metatype("ndpi_flow_t", {
   __new = flow_new;
   __gc  = lib.ndpi_free_flow;
})

---------------------------------------------------- Detection Module ------

local function detection_module_free(dm)
   lib.ndpi_exit_detection_module(ffi.gc(dm, nil), C.free)
end

local function detection_module_new(ctype, ticks_per_second)
   return lib.ndpi_init_detection_module(ticks_per_second, C.malloc, C.free, nil)
end

local detection_module = {
   load_protocols_file = function (self, path)
      if lib.ndpi_load_protocols_file(self, path) ~= 0 then
         error("Unable to open file '" .. path .. "'")
      end
      return self  -- Allow chaining calls
   end;

   set_protocol_bitmask = function (self, bitmask)
      lib.ndpi_set_protocol_detection_bitmask2(self, bitmask)
      return self  -- Allow chaining calls
   end;

   process_packet = function (...)
      local proto = lib.ndpi_detection_process_packet(...)
      return proto.master_protocol, proto.protocol
   end;

   find_port_based_protocol = function (...)
      local proto = lib.ndpi_find_port_based_protocol(...)
      return proto.master_protocol, proto.protocol
   end;

   guess_undetected_protocol = function (...)
      local proto = lib.ndpi_guess_undetected_protocol(...)
      return proto.master_protocol, proto.protocol
   end;

   get_protocol_id = function (...)
      local ret = lib.ndpi_get_protocol_id(...)
      return (ret == -1) and nil or ret
   end;

   get_protocol_breed = lib.ndpi_get_proto_breed;
   dump_protocols = lib.ndpi_dump_protocols;
}

local detection_module_type = ffi.metatype("ndpi_detection_module_t", {
   __index = detection_module;
   __new   = detection_module_new;
   __gc    = detection_module_free;
})

------------------------------------------------------------- Exports ------

return {
   id               = id_type;
   flow             = flow_type;
   detection_module = detection_module_type;
   protocol_bitmask = require("ndpi.protocol_bitmask").meta_type;
   protocol         = require("ndpi.protocol_ids");
}
