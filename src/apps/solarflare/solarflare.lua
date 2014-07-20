module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local lib    = require("core.lib")
local freelist = require("core.freelist")
local memory   = require("core.memory")
local buffer   = require("core.buffer")
local packet   = require("core.packet")
                 require("apps.solarflare.ef_vi_h")

local ciul = ffi.load("ciul")

local ef_vi_version = ffi.string(ciul.ef_vi_version_str())
print("ef_vi loaded, version " .. ef_vi_version)

-- common utility functions

ffi.cdef[[
char *strerror(int errnum);
]]

local function try (rc, message)
   if rc < 0 then
      error(string.format("%s failed: %s", message, ffi.string(C.strerror(ffi.errno()))))
   end
   return rc
end

SolarFlareNic = {}
SolarFlareNic.__index = SolarFlareNic
SolarFlareNic.version = ef_vi_version

function SolarFlareNic:new (args)
   args = config.parse_app_args(args)
end

function SolarFlareNic.open_device (interface_name)
   print("open device " .. interface_name)
   local try_ = try
   local function try (rc, message)
      return try_(rc, string.format("%s (if=%s)", message, interface_name))
   end

   local handle_p = ffi.new("ef_driver_handle[1]")
   try(ciul.ef_driver_open(handle_p), "ef_driver_open")
   local driver_handle = handle_p[0]
   print(string.format("driver handle %d", driver_handle));
   local pd_p = ffi.new("ef_pd[1]")
   try(ciul.ef_pd_alloc_by_name(pd_p, driver_handle, interface_name, C.EF_PD_DEFAULT + C.EF_PD_PHYS_MODE), "ef_pd_alloc_by_name")
   local fi_p = ffi.new("ef_vi[1]")
   try(ciul.ef_vi_alloc_from_pd(fi_p, driver_handle, pd_p, driver_handle,
                                   -1, -1, -1, nil, -1, C.EF_VI_TX_PUSH_DISABLE))
end
   
