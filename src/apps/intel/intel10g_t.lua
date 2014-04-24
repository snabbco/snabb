local lib      = require("core.lib")
local packet = require "core.packet"
local link     = require("core.link")
local config = require("core.config")
local app      = require("core.app")
local basic_apps = require("apps.basic.basic_apps")
local Intel82599 = require "apps.intel.intel_app".Intel82599


local PCIdevA = os.getenv("SNABB_TEST_INTEL10G_PCIDEVA")
local PCIdevB = os.getenv("SNABB_TEST_INTEL10G_PCIDEVB")


local function _unhex(s)
   local d = {}
   for b in s:gmatch('[0-9a-fA-F][0-9a-fA-F]') do
      d[#d+1] = tonumber(b, 16)
   end
   return string.char(unpack(d))
end

local function pad(s, n)
   if not n then return s end
   return (s..('\0'):rep(n)):sub(1, n)
end

local function make_packet(s, padlen)
   return packet.from_data(
      _unhex('FF:FF:FF:FF:FF:FF')..
      _unhex('52:54:00:01:01:01')..
      _unhex('08:00')..
      pad(s, padlen)..
      _unhex('00 00 00 00')
   )
end

local function make_split_packet(s, padlen)
   return packet.from_data(
      _unhex('FF:FF:FF:FF:FF:FF')..
      _unhex('52:54:00:01:01:01')..
      _unhex('08:00'),
      pad(s, padlen)..
      _unhex('00 00 00 00')
   )
end

local function _set_dst(p, dst)
   if #dst ~= 6 then dst = _unhex(dst) end
   assert(#dst==6, "wrong address length")
   packet.fill_data(p, dst, 0)
   return p
end

local function _set_src(p, src)
   if #src ~= 6 then src = _unhex(src) end
   assert(#src==6, "wrong address length")
   packet.fill_data(p, src, 6)
   return p
end


return {   
   sf_to_sf = PCIdevA and PCIdevB and {
      __setup = function ()
         local c = config.new()
         config.app(c, 'source1', basic_apps.Join)
--         config.app(c, 'source2', basic_apps.Source)
         config.app(c, 'nicA', Intel82599, ([[{pciaddr='%s'}]]):format(PCIdevA))
         config.app(c, 'nicB', Intel82599, ([[{pciaddr='%s'}]]):format(PCIdevB))
         config.app(c, 'sink', basic_apps.Classifier)
         config.link(c, 'source1.out -> nicA.rx')
--         config.link(c, 'source2.out -> nicB.rx')
         config.link(c, 'nicA.tx -> sink.in1')
         config.link(c, 'nicB.tx -> sink.in2')
         app.configure(c)
      end,
      
      t = {
         single_iovec = {
            broadcast = function ()
               local p = make_packet('some payload', 42)
               _set_dst(p, 'FF:FF:FF:FF:FF:FF')
               app.app_table.sink:setPatterns({same=packet.tostring(p)})
               link.transmit(app.app_table.source1.output.out, p)
               app.main({duration = 1, report={showlinks=false}})
               assert(app.app_table.sink:repSequence() == 'in2:same')
            end,
            unicast = function ()
               local p = make_packet('some payload', 42)
               _set_dst(p, '52:54:00:01:01:01')
               app.app_table.sink:setPatterns({same=packet.tostring(p)})
               link.transmit(app.app_table.source1.output.out, p)
               app.main({duration = 1, report={showlinks=false}})
               assert(app.app_table.sink:repSequence() == 'in2:same')
            end,
         },
         
         split_header = {
            broadcast = function ()
               local p = make_split_packet('some payload', 42)
               _set_dst(p, 'FF:FF:FF:FF:FF:FF')
               app.app_table.sink:setPatterns({same=packet.tostring(p)})
               link.transmit(app.app_table.source1.output.out, p)
               app.main({duration = 1, report={showlinks=false}})
               assert(app.app_table.sink:repSequence() == 'in2:same')
            end,
            unicast = function ()
               local p = make_split_packet('some payload', 42)
               _set_dst(p, '52:54:00:01:01:01')
               app.app_table.sink:setPatterns({same=packet.tostring(p)})
               link.transmit(app.app_table.source1.output.out, p)
               app.main({duration = 1, report={showlinks=false}})
               assert(app.app_table.sink:repSequence() == 'in2:same')
            end,
         },
      },
   } or false,
   
   sf_to_vf = PCIdevA and PCIdevB and {
      __setup = function ()
         local c = config.new()
         config.app(c, 'source1', basic_apps.Join)
         config.app(c, 'nicAs', Intel82599, ([[{
         -- Single App on NIC A
            pciaddr = '%s',
            macaddr = '52:54:00:01:01:01',
         }]]):format(PCIdevA))
         config.app(c, 'nicBm0', Intel82599, ([[{
         -- first VF on NIC B
            pciaddr = '%s',
            vmdq = true,
            macaddr = '52:54:00:02:02:02',
         }]]):format(PCIdevB))
         config.app(c, 'nicBm1', Intel82599, ([[{
         -- second VF on NIC B
            pciaddr = '%s',
            vmdq = true,
            macaddr = '52:54:00:03:03:03',
         }]]):format(PCIdevB))
         config.app(c, 'sink', basic_apps.Classifier)
         config.link(c, 'source1.out -> nicAs.rx')
         config.link(c, 'nicAs.tx -> sink.in1')
         config.link(c, 'nicBm0.tx -> sink.in2')
         config.link(c, 'nicBm1.tx -> sink.in3')
         app.configure(c)
      end,
      t = {
         single_iovec = {
            broadcast = function ()
               local p = make_packet('broadcast content', 42)
               _set_dst(p, 'FF:FF:FF:FF:FF:FF')
               app.app_table.sink:setPatterns({same=packet.tostring(p)})
               link.transmit(app.app_table.source1.output.out, p)
               app.main({duration = 1, report={showlinks=false}})
               assert(app.app_table.sink:repSequence() == 'in2:same,in3:same')
            end,
            unicast = function ()
               local p = make_packet('some payload', 42)
               _set_dst(p, '52:54:00:02:02:02')
               app.app_table.sink:setPatterns({same=packet.tostring(p)})
               link.transmit(app.app_table.source1.output.out, p)
               app.main({duration = 1, report={showlinks=false}})
               assert(app.app_table.sink:repSequence() == 'in2:same')
            end,
         },
         split_header = {
            broadcast = function ()
               local p = make_split_packet('broadcast content', 42)
               _set_dst(p, 'FF:FF:FF:FF:FF:FF')
               app.app_table.sink:setPatterns({same=packet.tostring(p)})
               link.transmit(app.app_table.source1.output.out, p)
               app.main({duration = 1, report={showlinks=false}})
               assert(app.app_table.sink:repSequence() == 'in2:same,in3:same')
            end,
            unicast = function ()
               local p = make_split_packet('some payload', 42)
               _set_dst(p, '52:54:00:02:02:02')
               app.app_table.sink:setPatterns({same=packet.tostring(p)})
               link.transmit(app.app_table.source1.output.out, p)
               app.main({duration = 1, report={showlinks=false}})
               assert(app.app_table.sink:repSequence() == 'in2:same')
            end,
         },
      },
   } or false,
}