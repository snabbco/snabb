module(..., package.seeall)

local lib        = require("core.lib")
local logger     = lib.logger_new({ rate = 32, module = 'minapp' });
local intel      = require("apps.intel_mp.intel_mp")
local ipv4_apps  = require("apps.jit_loop.ipv4_apps")

function run (parameters)
   local north_pci_address   = "0000:01:00.1"
   local south_pci_address   = "0000:01:00.0"
   local north_mac           = "08:35:71:02:6a:63"
   local south_mac           = "08:35:71:02:6a:62"
   local north_next_hop_mac  = "08:35:71:00:97:15"
   local south_next_hop_mac  = "08:35:71:00:97:14"
   
   local south_if_config     = {pciaddr=south_pci_address, rxq = 0, txq = 0}
   local north_if_config     = {pciaddr=north_pci_address, rxq = 0, txq = 0}
   
   local north_mac_config    = {src_eth = north_mac, dst_eth = north_next_hop_mac}
   local south_mac_config    = {src_eth = south_mac, dst_eth = south_next_hop_mac}

   local c = config.new()
   config.app(c, "south_if",       intel.Intel, south_if_config)
   config.app(c, "north_if",       intel.Intel, north_if_config)
   config.app(c, "north_setmac",   ipv4_apps.ChangeMAC, north_mac_config)
   config.app(c, "south_setmac",   ipv4_apps.ChangeMAC, south_mac_config)

   config.link(c, "south_if.output         -> north_setmac.input")
   config.link(c, "north_setmac.output     -> north_if.input")

   config.link(c, "north_if.output         -> south_setmac.input")
   config.link(c, "south_setmac.output     -> south_if.input")

   engine.configure(c)
   logger:log ("Engine ready to start processing")
   engine.main({report = {showlinks=true, showapps=true}})
end
