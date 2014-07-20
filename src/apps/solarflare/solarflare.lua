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
   assert(args.ifname)
   return setmetatable(args, { __index = SolarFlareNic })
end

function SolarFlareNic:open ()
   local try_ = try
   local function try (rc, message)
      return try_(rc, string.format("%s (if=%s)", message, self.ifname))
   end

   local handle_p = ffi.new("ef_driver_handle[1]")
   try(ciul.ef_driver_open(handle_p), "ef_driver_open")
   self.driver_handle = handle_p[0]
   self.pd_p = ffi.new("ef_pd[1]")
   try(ciul.ef_pd_alloc_by_name(self.pd_p, self.driver_handle, self.ifname, C.EF_PD_DEFAULT + C.EF_PD_PHYS_MODE), "ef_pd_alloc_by_name")
   self.ef_vi_p = ffi.new("ef_vi[1]")
   try(ciul.ef_vi_alloc_from_pd(self.ef_vi_p, self.driver_handle, self.pd_p, self.driver_handle,
                                   -1, -1, -1, nil, -1, C.EF_VI_TX_PUSH_DISABLE))

   self.mac_address = ffi.new("unsigned char[6]");
   try(ciul.ef_vi_get_mac(self.ef_vi_p, self.driver_handle, self.mac_address))
   self.mtu = try(ciul.ef_vi_mtu(self.ef_vi_p, self.driver_handle))
   print(string.format("Opened SolarFlare interface %s (MAC address %02x:%02x:%02x:%02x:%02x:%02x, MTU %d)",
                       self.ifname,
                       self.mac_address[0], self.mac_address[1], self.mac_address[2], self.mac_address[3], self.mac_address[4], self.mac_address[5],
                       self.mtu));
end
   
