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

function inputs.intel10g (kind, device)
   local conf = { pciaddr = device }
   return "tx", { require("apps.intel.intel_app").Intel82599, conf }
end

function inputs.intel1g (kind, device)
   local conf = { pciaddr = device }
   return "tx", { require("apps.intel.intel1g").Intel1g, conf }
end
