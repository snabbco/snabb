local ffi = require("ffi")
local C = ffi.C
local memory = require "core.memory"
memory.allocate_RAM = C.malloc
memory.ram_to_io_addr = memory.virtual_to_physical
local buffer = require "core.buffer"
local packet = require "core.packet"


return {
   from_data = function ()
      local p = packet.from_data('abcdefghijklmnopqrstuvwxyz')
      assert (packet.tostring(p) == 'abcdefghijklmnopqrstuvwxyz')
   end,
   
   add_iovec = {
      
      to_empty_packet = function ()
         local p = packet.allocate()
         local b = buffer.from_data('abcdefghijklmnopqrstuvwxyz')
         packet.add_iovec(p, b, 26, 0)
         assert (p.niovecs == 1)
         assert (p.length == 26)
         assert (buffer.tostring(p.iovecs[0].buffer, 26) == 'abcdefghijklmnopqrstuvwxyz')
         assert (packet.tostring(p) == 'abcdefghijklmnopqrstuvwxyz')
      end,
      
      to_single_iovec_packet = function ()
         local p = packet.from_data('abcdefghijklm')
         local b = buffer.from_data('nopqrstuvwxyz')
         packet.add_iovec(p, b, 13, 0)
         assert (p.niovecs == 2)
         assert (p.length == 26)
         assert (buffer.tostring(p.iovecs[0].buffer, 13) == 'abcdefghijklm')
         assert (buffer.tostring(p.iovecs[1].buffer, 13) == 'nopqrstuvwxyz')
         assert (packet.tostring(p) == 'abcdefghijklmnopqrstuvwxyz')
      end,
   },
   
   prepend_iovec = {
      
      to_empty_packet = function ()
         local p = packet.allocate()
         local b = buffer.from_data('abcdefghijklmnopqrstuvwxyz')
         packet.prepend_iovec(p, b, 26, 0)
         assert (p.niovecs == 1)
         assert (p.length == 26)
         assert (buffer.tostring(p.iovecs[0].buffer, 26) == 'abcdefghijklmnopqrstuvwxyz')
         assert (packet.tostring(p) == 'abcdefghijklmnopqrstuvwxyz')
      end,
      
      to_single_iovec_packet = function ()
         local p = packet.from_data('nopqrstuvwxyz')
         local b = buffer.from_data('abcdefghijklm')
         packet.prepend_iovec(p, b, 13, 0)
         assert (p.niovecs == 2)
         assert (p.length == 26)
         assert (buffer.tostring(p.iovecs[0].buffer, 13) == 'abcdefghijklm')
         assert (buffer.tostring(p.iovecs[1].buffer, 13) == 'nopqrstuvwxyz')
         assert (packet.tostring(p) == 'abcdefghijklmnopqrstuvwxyz')
      end,
   },
   
   coalesce = function ()
      local p = packet.from_data('abcdefghijklm')
      local b = buffer.from_data('nopqrstuvwxyz')
      packet.add_iovec(p, b, 13, 0)
      assert (p.niovecs == 2)
      assert (p.length == 26)
      assert (packet.tostring(p) == 'abcdefghijklmnopqrstuvwxyz')
      packet.coalesce(p)
      assert (p.niovecs == 1)
      assert (p.length == 26)
      assert (packet.tostring(p) == 'abcdefghijklmnopqrstuvwxyz')
   end,
   
   fill_data = {
      
      at_start = {
         to_single_iovec_packet = function ()
            local p = packet.from_data('abcdefghijklmnopqrstuvwxyz')
            packet.fill_data(p, '12345678')
            assert (packet.tostring(p) == '12345678ijklmnopqrstuvwxyz')
         end,
         
         to_first_of_multi_iovec_packet = function ()
            local p = packet.allocate()
            packet.add_iovec(p, buffer.from_data('abcdefghijklm'), 13, 0)
            packet.add_iovec(p, buffer.from_data('nopqrstuvwxyz'), 13, 0)
            packet.fill_data(p, '12345678', 0)
            assert (packet.tostring(p) == '12345678ijklmnopqrstuvwxyz')
         end,
         
         to_two_of_multi_iovec_packet = function ()
            local p = packet.allocate()
            packet.add_iovec(p, buffer.from_data('abcdefghijklm'), 13, 0)
            packet.add_iovec(p, buffer.from_data('nopqrstuvwxyz'), 13, 0)
            packet.fill_data(p, '12345678', 0)
            assert (packet.tostring(p) == '12345678ijklmnopqrstuvwxyz')
         end,
      },
      at_offset = {
         to_single_iovec_packet = function ()
            local p = packet.from_data('abcdefghijklmnopqrstuvwxyz')
            packet.fill_data(p, '12345678', 3)
            assert (packet.tostring(p) == 'abc12345678lmnopqrstuvwxyz')
         end,
         
         to_first_of_multi_iovec_packet = function ()
            local p = packet.allocate()
            packet.add_iovec(p, buffer.from_data('abcdefghijklm'), 13, 0)
            packet.add_iovec(p, buffer.from_data('nopqrstuvwxyz'), 13, 0)
            packet.fill_data(p, '12345678', 3)
            assert (packet.tostring(p) == 'abc12345678lmnopqrstuvwxyz')
         end,
         
         to_second_of_multi_iovec_packet = function ()
            local p = packet.allocate()
            packet.add_iovec(p, buffer.from_data('abcdefghijklm'), 13, 0)
            packet.add_iovec(p, buffer.from_data('nopqrstuvwxyz'), 13, 0)
            packet.fill_data(p, '12345678', 15)
            assert (packet.tostring(p) == 'abcdefghijklmno12345678xyz')
         end,
         
         to_two_of_multi_iovec_packet = function ()
            local p = packet.allocate()
            packet.add_iovec(p, buffer.from_data('abcdefghijklm'), 13, 0)
            packet.add_iovec(p, buffer.from_data('nopqrstuvwxyz'), 13, 0)
            packet.fill_data(p, '12345678', 9)
            assert (packet.tostring(p) == 'abcdefghi12345678rstuvwxyz')
         end,
         
         to_three_of_multi_iovec_packet = function ()
            local p = packet.allocate()
            packet.add_iovec(p, buffer.from_data('abcdefghijk'), 11, 0)
            packet.add_iovec(p, buffer.from_data('lmno'), 4, 0)
            packet.add_iovec(p, buffer.from_data('pqrstuvwxyz'), 11, 0)
            packet.fill_data(p, '12345678', 9)
            assert (packet.tostring(p) == 'abcdefghi12345678rstuvwxyz')
         end,
      },
   },
}