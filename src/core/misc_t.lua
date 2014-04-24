local ffi= require("ffi")
local lib = require("core.lib")
local timer = require("core.timer")
local link = require("core.link")
local packet = require("core.packet")
local memory = require("core.memory")

return {
   timer = function ()
      timer.ticks = 0
      local ntimers, runtime = 10000, 100000
      local count, expected_count = 0, 0
      local fn = function (t) count = count + 1 end
      -- Start timers, each counting at a different frequency
      for freq = 1, ntimers do
         local t = timer.new("timer"..freq, fn, timer.ns_per_tick * freq, 'repeating')
         timer.activate(t)
         expected_count = expected_count + math.floor(runtime / freq)
      end
      -- Run timers for 'runtime' in random sized time steps
      local now_ticks = 0
      while now_ticks < runtime do
         now_ticks = math.min(runtime, now_ticks + math.random(5))
         local old_count = count
         timer.run_to_time(now_ticks * timer.ns_per_tick)
         assert(count > old_count, "count increasing")
      end
      assert(count == expected_count, "final count correct")
      print("ok ("..lib.comma_value(count).." callbacks)")
   end,
   
   lib = function ()
      local data = "\x45\x00\x00\x73\x00\x00\x40\x00\x40\x11\xc0\xa8\x00\x01\xc0\xa8\x00\xc7"
      local cs = lib.csum(data, string.len(data))
      assert(cs == 0xb861, "bad checksum: " .. lib.bit.tohex(cs, 4))
      
   --    assert(readlink('/etc/rc2.d/S99rc.local') == '../init.d/rc.local', "bad readlink")
   --    assert(dirname('/etc/rc2.d/S99rc.local') == '/etc/rc2.d', "wrong dirname")
   --    assert(basename('/etc/rc2.d/S99rc.local') == 'S99rc.local', "wrong basename")
      assert(lib.hexdump('\x45\x00\xb6\x7d\x00\xFA\x40\x00\x40\x11'):upper()
            :match('^45.00.B6.7D.00.FA.40.00.40.11$'), "wrong hex dump")
      assert(lib.hexundump('4500 B67D 00FA400040 11', 10)
            =='\x45\x00\xb6\x7d\x00\xFA\x40\x00\x40\x11', "wrong hex undump")
   end,
   
   link = function ()
      local r = link.new()
      local p = packet.allocate()
      packet.tenure(p)
      assert(r.stats.txpackets == 0 and link.empty(r) == true  and link.full(r) == false)
      assert(link.nreadable(r) == 0)
      link.transmit(r, p)
      assert(r.stats.txpackets == 1 and link.empty(r) == false and link.full(r) == false)
      for i = 1, link.max-2 do
         link.transmit(r, p)
      end
      assert(r.stats.txpackets == link.max-1 and link.empty(r) == false and link.full(r) == false)
      assert(link.nreadable(r) == r.stats.txpackets)
      link.transmit(r, p)
      assert(r.stats.txpackets == link.max   and link.empty(r) == false and link.full(r) == true)
      link.transmit(r, p)
      assert(r.stats.txpackets == link.max and r.stats.txdrop == 1)
      assert(not link.empty(r) and link.full(r))
      while not link.empty(r) do
         link.receive(r)
      end
      assert(r.stats.rxpackets == link.max)
   end,
   
   memory = function ()
      require("lib.hardware.bus")
      print("HugeTLB pages (/proc/sys/vm/nr_hugepages): " .. memory.get_hugepages())
      for i = 1, 4 do
         print("  Allocating a "..(memory.huge_page_size/1024/1024).."MB HugeTLB: ")
--         io.flush()
         local dmaptr, physptr, dmalen = memory.dma_alloc(memory.huge_page_size)
         print("Got "..(dmalen/1024^2).."MB "..
            "at 0x"..tostring(ffi.cast("void*",tonumber(physptr))))
         ffi.cast("uint32_t*", dmaptr)[0] = 0xdeadbeef -- try a write
         assert(dmaptr ~= nil and dmalen == memory.huge_page_size)
      end
      print("HugeTLB pages (/proc/sys/vm/nr_hugepages): " .. memory.get_hugepages())
      print("HugeTLB page allocation OK.")
   end
      
   }
