module(..., package.seeall)

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

function inputs.intel (kind, device)
   local conf = { pciaddr = device, rxq = 0 }
   return "output", { require("apps.intel_mp.intel_mp").driver, conf }
end
