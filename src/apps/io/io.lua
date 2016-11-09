-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- ABSTRACT
--
-- The IOControl and IO macro apps implement the following interface:
--
-- config.app(c, "ctrl", IOControl,
--            {pciaddr="01:00.0",
--             queues = {{id="a", macaddr="10:10:10:10:10:10", vlan=42, buckets=2},
--                       {id="b", macaddr="20:20:20:20:20:20", vlan=43}}})
--
-- config.app(c, "io", IO, {pciaddr="01:00.0", queue = "a", bucket = 1})
--
-- All keys except `queues', `id', `buckets', `queue', and `bucket' are driver
-- dependent.
--
-- To add support for a PCI driver module it must be registered in
-- lib.hardware.pci. To add support for a virtual driver module it must be
-- registered in the `virtual_module' table below.
--
-- The driver module must expose a `driver' variable that contains the app that
-- implements the queue driver. If a control app is required for queue setup,
-- the driver must expose a `control' variable that contains the respective
-- app, which must accept the configuration argument passed to IOControl.
--
-- Note that the `buckets' and `bucket' properties must default to 1.
--
-- Finally, a configuration `formula' for the driver must be selected. See how
-- the `formula' table is populated below.
--
-- FURTHER USAGE EXAMPLES
--
-- config.app(c, "ctrl", IOControl,
--            {virtual="tap",
--             queues = {{id="a", ifname="foo"}}})
--
-- config.app(c, "tap_a", IO, {virtual="tap", queue="a"})
--
-- config.app(c, "ctrl", IOControl,
--            {virtual="emu",
--             queues = {{id="a", macaddr="10:10:10:10:10:10", buckets=2}}})
--
-- config.app(c, "emu_a", IO, {virtual="emu", queue="a", bucket=1})

module(..., package.seeall)
local lib = require("core.lib")
local pci = require("lib.hardware.pci")

virtual_module = {}
formula = {}

IOControl = {
   config = {
      pciaddr = {}, virtual = {},
      queues = {required=true}
   }
}

local queues = {}; setmetatable(queues, {__mode="k"}) -- Weak keys

function IOControl:configure (c, name, conf)
   local module
   if conf.pciaddr then
      module = require(pci.device_info(conf.pciaddr).driver)
   elseif conf.virtual then
      module = require(virtual_module[conf.virtual])
   else
      error("Must supply one of: pciaddr, virtual")
   end
   if module.control then
      config.app(c, name, module.control, conf)
   end
   queues[c] = queues[c] or {}
   queues[c][conf.pciaddr or conf.virtual] = conf.queues
end


IO = {
   config = {
      pciaddr = {}, virtual = {},
      queue = {required=true},
      bucket = {}
   }
}

local function make_queueconf (c, conf)
   local hub = conf.pciaddr or conf.virtual or fallback
   local queueconf
   for _, queuespec in ipairs(queues[c][hub]) do
      if queuespec.id == conf.queue then
         queueconf = lib.deepcopy(queuespec)
         break
      end
   end
   -- Delete IOControl specific keys, set pciaddr if applicable.
   queueconf.id = nil
   local buckets = queueconf.buckets
   queueconf.buckets = nil
   queueconf.pciaddr = conf.pciaddr
   return queueconf, buckets
end

function IO:configure (c, name, conf)
   assert(conf.queue, "IO: conf needs `queue'")
   local modulepath
   if conf.pciaddr then
      modulepath = pci.device_info(conf.pciaddr).driver
   elseif conf.virtual then
      modulepath = virtual_module[conf.virtual]
   else
      error("Must supply one of: pciaddr, virtual")
   end
   formula[modulepath](c, name, require(modulepath).driver,
                       conf.queue, conf.bucket, make_queueconf(c, conf))
end


local function app_using_conf
   (c, name, driver, queue, bucket, conf)
   config.app(c, name, driver, conf)
end

local function app_using_ifname
   (c, name, driver, queue, bucket, conf)
   config.app(c, name, driver, conf.ifname)
end

local function app_using_everything
   (c, name, driver, queue, bucket, conf, buckets)
   config.app(c, name, driver, {pciaddr=conf.pciaddr,
                                queue=queue,
                                bucket=bucket,
                                buckets=buckets,
                                queueconf=conf})
end


formula['apps.intel.intel_app'] = app_using_conf

formula['apps.solarflare.solarflare'] = app_using_conf

virtual_module.vhost = 'apps.vhost.vhost_user'
formula['apps.vhost.vhost_user'] = app_using_conf

virtual_module.tap = 'apps.tap.tap'
formula['apps.tap.tap'] = app_using_ifname

virtual_module.raw = 'apps.socket.raw'
formula['apps.socket.raw'] = app_using_ifname

virtual_module.emu = 'apps.io.emu'
formula['apps.io.emu'] = app_using_everything


function selftest ()
   local c = config.new()
   config.app(c, "IOControl", IOControl,
              {queues = {{id="a", macaddr="60:50:40:40:20:10", buckets=2}}})
   config.app(c, "a1", IO, {queue="a", bucket=1})
   config.app(c, "a2", IO, {queue="a", bucket=2})
   engine.configure(c)
   engine.report_apps()
   engine.report_links()
end