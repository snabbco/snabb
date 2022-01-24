-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local worker = require("core.worker")

local pci0 = "81:00.0"
local pci1 = "81:00.1"

local nworkers = 1
local nqueues = 1
local npackets = 100e6
local pktsize = 60

worker.start("sink", ('require("apps.mellanox.benchmark").sink(%q, {}, %d, %d)')
   :format(pci0, nworkers, nqueues))

worker.start("source", ('require("apps.mellanox.benchmark").source(%q, {}, %d, %d, nil, nil, nil, %d, %d)')
   :format(pci0, nworkers, nqueues, npackets, pktsize))

engine.main{done = function ()
   return not worker.status()["source"].alive
end}