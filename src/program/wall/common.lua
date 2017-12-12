-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local pci = require('lib.hardware.pci')

-- This module provides some common definitions for snabbwall programs

inputs = {}

function inputs.pcap (kind, path)
   return "output", { require("apps.pcap.pcap").PcapReader, path }
end

function inputs.raw (kind, device)
   return "tx", { require("apps.socket.raw").RawSocket, device }
end

function inputs.tap (kind, device)
   return "output", { require("apps.tap.tap").Tap, device }
end

function inputs.pci (kind, device)
   local info = pci.device_info(device)
   assert(info.usable == 'yes', "Unusable PCI device: "..device)
   local conf = { pciaddr = info.pciaddress }
   return info.tx, { require(info.driver).driver, conf }
end
