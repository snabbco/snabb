-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local shm = require("core.shm")
local ifmib = require("lib.ipc.shmem.iftable_mib")

local ifmib_dir = '/ifmib'

local function create_ifmib(stats, ifname, ifalias, log_date)
    -- stats can be nil in case this process is not the master
    -- of the device
    if not stats then return end
    if not shm.exists(ifmib_dir) then
       shm.mkdir(ifmib_dir)
    end
    ifmib.init_snmp( { ifDescr = ifname,
                       ifName = ifname,
                       ifAlias = ifalias or "NetFlow input", },
       ifname:gsub('/', '-'), stats,
       shm.root..ifmib_dir, 5, log_date)
 end

MIB = {
    config = {
        target_app = {required=true},
        ifname = {required=true},
        ifalias = {default="NetFlow input"},
        log_date = {default=false},
        stats = {default='shm'}
    }
}

function MIB:new (conf)
    local self = {
        initialized = false,
        conf = conf
    }
    return setmetatable(self, {__index=MIB})
end

function MIB:tick ()
    if self.initialized then
        return
    end

    local target_app = engine.app_table[self.conf.target_app]
    local stats = target_app and target_app[self.conf.stats]
    create_ifmib(stats, self.conf.ifname, self.conf.ifalias, self.conf.log_date)
    self.initialized = true
end