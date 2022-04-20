-- AFTR Binding Table
--
-- A binding table is a collection of softwires (tunnels).  One endpoint
-- of the softwire is in the AFTR and the other is in the B4.  A
-- softwire provisions an IPv4 address (or a part of an IPv4 address) to
-- a customer behind a B4.  The B4 arranges for all IPv4 traffic to be
-- encapsulated in IPv6 and sent to the AFTR; the AFTR does the reverse.
-- The binding table is how the AFTR knows which B4 is associated with
-- an incoming packet.
--
-- There are three parts of a binding table: the PSID info map, the
-- border router (BR) address table, and the softwire map.
--
-- The PSID info map facilitates IPv4 address sharing.  The lightweight
-- 4-over-6 architecture supports sharing of IPv4 addresses by
-- partitioning the space of TCP/UDP/ICMP ports into disjoint "port
-- sets".  Each softwire associated with an IPv4 address corresponds to
-- a different set of ports on that address.  The way that the ports are
-- partitioned is specified in RFC 7597: each address has an associated
-- set of parameters that specifies how to compute a "port set
-- identifier" (PSID) from a given port.
--
--                      0                   1
--                      0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5
--                     +-----------+-----------+-------+
--       Ports in      |     A     |    PSID   |   j   |
--    the CE port set  |    > 0    |           |       |
--                     +-----------+-----------+-------+
--                     |  a bits   |  k bits   |m bits |
--
--             Figure 2: Structure of a Port-Restricted Port Field
--
--   Source: http://tools.ietf.org/html/rfc7597#section-5.1
--
-- We find the specification's names to be a bit obtuse, so we refer to
-- them using the following names:
--
--   a bits = reserved_ports_bit_count.
--   k bits = psid_length.
--   m bits = shift.
--
-- When a packet comes in, we take the IPv4 address and look up the PSID
-- parameters from the PSID info table.  We use those parameters to
-- compute the PSID.  Together, the IPv4 address and PSID are used as a
-- key into the softwire table, which determines if the packet
-- corresponds to a known softwire, and if so the IPv6 address of the B4.
--
-- A successful lookup into the softwire table will also indicate the
-- IPv6 address of the AFTR itself.  As described in
-- https://www.ietf.org/id/draft-farrer-softwire-br-multiendpoints-01.txt,
-- an AFTR may have multiple configured addresses.
--
-- Note that if reserved_ports_bit_count is nonzero, the lwAFTR must
-- drop a packet whose port is less than 2^reserved_ports_bit_count.  In
-- practice though we just return a PSID that is out of range (greater
-- or equal to 2^psid_length), which will cause the softwire lookup to
-- fail.  Likewise if we get a packet to an IPv4 address that's not
-- under our control, we return 0 for the PSID, knowing that the
-- subsequent softwire lookup will fail.
--
module(..., package.seeall)

local bit = require('bit')
local ffi = require("ffi")
local rangemap = require("apps.lwaftr.rangemap")
local ctable = require("lib.ctable")
local ipv6 = require("lib.protocol.ipv6")
local ipv4_ntop = require("lib.yang.util").ipv4_ntop

local band, lshift, rshift = bit.band, bit.lshift, bit.rshift

psid_map_key_t = ffi.typeof[[
   struct { uint32_t addr; }
]]
psid_map_value_t = ffi.typeof[[
   struct { uint16_t psid_length; uint16_t shift; }
]]

BTLookupQueue = {}

-- BTLookupQueue needs a binding table to get softwires and PSID lookup.
function BTLookupQueue.new(binding_table)
   local ret = {
      binding_table = assert(binding_table),
   }
   ret.streamer = binding_table.softwires:make_lookup_streamer(32)
   ret.packet_queue = ffi.new("struct packet * [32]")
   ret.length = 0
   return setmetatable(ret, {__index=BTLookupQueue})
end

function BTLookupQueue:enqueue_lookup(pkt, ipv4, port)
   local n = self.length
   local streamer = self.streamer
   streamer.entries[n].key.ipv4 = ipv4
   streamer.entries[n].key.psid = port
   self.packet_queue[n] = pkt
   n = n + 1
   self.length = n
   return n == 32
end

function BTLookupQueue:process_queue()
   if self.length > 0 then
      local streamer = self.streamer
      for n = 0, self.length-1 do
         local ipv4 = streamer.entries[n].key.ipv4
         local port = streamer.entries[n].key.psid
         streamer.entries[n].key.psid = self.binding_table:lookup_psid(ipv4, port)
      end
      streamer:stream()
   end
   return self.length
end

function BTLookupQueue:get_lookup(n)
   if n < self.length then
      local streamer = self.streamer
      local pkt, b4_ipv6, br_ipv6
      pkt = self.packet_queue[n]
      if not streamer:is_empty(n) then
         b4_ipv6 = streamer.entries[n].value.b4_ipv6
         br_ipv6 = streamer.entries[n].value.br_address
      end
      return pkt, b4_ipv6, br_ipv6
   end
end

function BTLookupQueue:reset_queue()
   self.length = 0
end

local BindingTable = {}
local lookup_key
function BindingTable.new(psid_map, softwires)
   local ret = {
      psid_map = assert(psid_map),
      softwires = assert(softwires),
   }
   lookup_key = ret.softwires.entry_type().key
   return setmetatable(ret, {__index=BindingTable})
end

function BindingTable:add_softwire_entry(entry_blob)
   local entry = self.softwires.entry_type()
   assert(ffi.sizeof(entry) == ffi.sizeof(entry_blob))
   ffi.copy(entry, entry_blob, ffi.sizeof(entry_blob))
   self.softwires:add(entry.key, entry.value)
end

function BindingTable:remove_softwire_entry(entry_key_blob)
   local entry = self.softwires.entry_type()
   assert(ffi.sizeof(entry.key) == ffi.sizeof(entry_key_blob))
   ffi.copy(entry.key, entry_key_blob, ffi.sizeof(entry_key_blob))
   self.softwires:remove(entry.key)
end


function BindingTable:lookup(ipv4, port)
   local psid = self:lookup_psid(ipv4, port)
   lookup_key.ipv4 = ipv4
   lookup_key.psid = psid
   local entry = self.softwires:lookup_ptr(lookup_key)
   if entry then return entry.value end
   return nil
end

function BindingTable:is_managed_ipv4_address(ipv4)
   -- The PSID info map covers only the addresses that are declared in
   -- the binding table.  Other addresses are recorded as having
   -- psid_length == shift == 0.
   local psid_info = self.psid_map:lookup(ipv4).value
   return psid_info.psid_length + psid_info.shift > 0
end

function BindingTable:lookup_psid(ipv4, port)
   local psid_info = self.psid_map:lookup(ipv4).value
   local psid_len, shift = psid_info.psid_length, psid_info.shift
   local psid_mask = lshift(1, psid_len) - 1
   local psid = band(rshift(port, shift), psid_mask)
   -- Are there any restricted ports for this address?
   if psid_len + shift < 16 then
      local reserved_ports_bit_count = 16 - psid_len - shift
      local first_allocated_port = lshift(1, reserved_ports_bit_count)
      -- The port is within the range of restricted ports.  Assign a
      -- bogus PSID so that lookup will fail.
      if port < first_allocated_port then psid = psid_mask + 1 end
   end
   return psid
end

-- Iterate over the set of IPv4 addresses managed by a binding
-- table. Invoke like:
--
--   for ipv4_lo, ipv4_hi, psid_info in bt:iterate_psid_map() do ... end
--
-- The IPv4 values are host-endianness uint32 values, and are an
-- inclusive range to which the psid_info applies.  The psid_info is a
-- psid_map_value_t pointer, which has psid_length and shift members.
function BindingTable:iterate_psid_map()
   local f, state, lo = self.psid_map:iterate()
   local function next_entry()
      local hi, value
      repeat
         lo, hi, value = f(state, lo)
         if lo == nil then return end
      until value.psid_length > 0 or value.shift > 0
      return lo, hi, value
   end
   return next_entry
end

-- Iterate over the softwires in a binding table.  Invoke like:
--
--   for entry in bt:iterate_softwires() do ... end
--
-- Each entry is a pointer with two members, "key" and "value".  They
-- key is a softwire_key_t and has "ipv4" and "psid" members.  The value
-- is a softwire_value_t and has "br_address" and "b4_ipv6" members. Both
-- members are a uint8_t[16].
function BindingTable:iterate_softwires()
   return self.softwires:iterate()
end

function pack_psid_map_entry (softwire)
   local port_set = assert(softwire.value.port_set)

   local psid_length = port_set.psid_length
   local shift = 16 - psid_length - (port_set.reserved_ports_bit_count or 0)

   assert(psid_length + shift <= 16,
            ("psid_length %s + shift %s should not exceed 16"):
               format(psid_length, shift))

   local key = softwire.key.ipv4
   local value = {psid_length = psid_length, shift = shift}

   return key, value
end

function load (conf)
   local psid_builder = rangemap.RangeMapBuilder.new(psid_map_value_t)

   -- Lets create an intermediatory PSID map to verify if we've added
   -- a PSID entry yet, if we have we need to verify that the values
   -- are the same, if not we need to error.
   local inter_psid_map = {
      keys = {}
   }
   function inter_psid_map:exists (key, value)
      local v = self.keys[key]
      if not v then return false end
      if v.psid_length ~= v.psid_length or v.shift ~= v.shift then
         error("Port set already added with different values: "..key)
      end
      return true
   end
   function inter_psid_map:add (key, value)
      self.keys[key] = value
   end

   for entry in conf.softwire:iterate() do
      -- Check that the map either hasn't been added or that
      -- it's the same value as one which has.
      local psid_key, psid_value = pack_psid_map_entry(entry)
      if not inter_psid_map:exists(psid_key, psid_value) then
         inter_psid_map:add(psid_key, psid_value)
         psid_builder:add(entry.key.ipv4, psid_value)
      end
   end

   local psid_map = psid_builder:build(psid_map_value_t(), true)
   return BindingTable.new(psid_map, conf.softwire)
end

function selftest()
   print('selftest: binding_table')
   local function load_str(str)
      local mem = require("lib.stream.mem")
      local yang = require('lib.yang.yang')
      local data = require('lib.yang.data')
      local schema = yang.load_schema_by_name('snabb-softwire-v3')
      local grammar = data.config_grammar_from_schema(schema)
      local subgrammar = assert(grammar.members['softwire-config'])
      local subgrammar = assert(subgrammar.members['binding-table'])
      local parse = data.data_parser_from_grammar(subgrammar)
      return load(parse(mem.open_input_string(str)))
   end
   local map = load_str([[
      softwire { ipv4 178.79.150.233; psid 80; b4-ipv6 127:2:3:4:5:6:7:128; br-address 8:9:a:b:c:d:e:f; port-set { psid-length 16; }}
      softwire { ipv4 178.79.150.233; psid 2300; b4-ipv6 127:11:12:13:14:15:16:128; br-address 8:9:a:b:c:d:e:f; port-set { psid-length 16; }}
      softwire { ipv4 178.79.150.233; psid 2700; b4-ipv6 127:11:12:13:14:15:16:128; br-address 8:9:a:b:c:d:e:f; port-set { psid-length 16; }}
      softwire { ipv4 178.79.150.233; psid 4660; b4-ipv6 127:11:12:13:14:15:16:128; br-address 8:9:a:b:c:d:e:f; port-set { psid-length 16; }}
      softwire { ipv4 178.79.150.233; psid 7850; b4-ipv6 127:11:12:13:14:15:16:128; br-address 8:9:a:b:c:d:e:f; port-set { psid-length 16; }}
      softwire { ipv4 178.79.150.233; psid 22788; b4-ipv6 127:11:12:13:14:15:16:128; br-address 8:9:a:b:c:d:e:f; port-set { psid-length 16; }}
      softwire { ipv4 178.79.150.233; psid 54192; b4-ipv6 127:11:12:13:14:15:16:128; br-address 8:9:a:b:c:d:e:f; port-set { psid-length 16; }}
      softwire { ipv4 178.79.150.15; psid 0; b4-ipv6 127:22:33:44:55:66:77:128; br-address 8:9:a:b:c:d:e:f; port-set { psid-length 4; }}
      softwire { ipv4 178.79.150.15; psid 1; b4-ipv6 127:22:33:44:55:66:77:128; br-address 8:9:a:b:c:d:e:f; port-set { psid-length 4; }}
      softwire { ipv4 178.79.150.2; psid 7850; b4-ipv6 127:24:35:46:57:68:79:128; br-address 1E:1:1:1:1:1:1:af; port-set { psid-length 16; }}
      softwire { ipv4 178.79.150.3; psid 4; b4-ipv6 127:14:25:36:47:58:69:128; br-address 1E:2:2:2:2:2:2:af; port-set { psid-length 6; }}
   ]])

   local ipv4_pton = require('lib.yang.util').ipv4_pton
   local ipv6_protocol = require("lib.protocol.ipv6")
   local function lookup(ipv4, port)
      return map:lookup(ipv4_pton(ipv4), port)
   end
   local function assert_lookup(ipv4, port, ipv6, br)
      local val = assert(lookup(ipv4, port))
      assert(ffi.C.memcmp(ipv6_protocol:pton(ipv6), val.b4_ipv6, 16) == 0)
      assert(ffi.C.memcmp(ipv6_protocol:pton(br), val.br_address, 16) == 0)
   end
   assert_lookup('178.79.150.233', 80, '127:2:3:4:5:6:7:128', '8:9:a:b:c:d:e:f')
   assert(lookup('178.79.150.233', 79) == nil)
   assert(lookup('178.79.150.233', 81) == nil)
   assert_lookup('178.79.150.15', 80, '127:22:33:44:55:66:77:128', '8:9:a:b:c:d:e:f')
   assert_lookup('178.79.150.15', 4095, '127:22:33:44:55:66:77:128', '8:9:a:b:c:d:e:f')
   assert_lookup('178.79.150.15', 4096, '127:22:33:44:55:66:77:128', '8:9:a:b:c:d:e:f')
   assert_lookup('178.79.150.15', 8191, '127:22:33:44:55:66:77:128', '8:9:a:b:c:d:e:f')
   assert(lookup('178.79.150.15', 8192) == nil)
   assert_lookup('178.79.150.2', 7850, '127:24:35:46:57:68:79:128', '1E:1:1:1:1:1:1:af')
   assert(lookup('178.79.150.3', 4095) == nil)
   assert_lookup('178.79.150.3', 4096, '127:14:25:36:47:58:69:128', '1E:2:2:2:2:2:2:af')
   assert_lookup('178.79.150.3', 5119, '127:14:25:36:47:58:69:128', '1E:2:2:2:2:2:2:af')
   assert(lookup('178.79.150.3', 5120) == nil)
   assert(lookup('178.79.150.4', 7850) == nil)

   do
      local psid_map_iter = {
         { ipv4_pton('178.79.150.2'), { psid_length=16, shift=0 } },
         { ipv4_pton('178.79.150.3'), { psid_length=6, shift=10 } },
         { ipv4_pton('178.79.150.15'), { psid_length=4, shift=12 } },
         { ipv4_pton('178.79.150.233'), { psid_length=16, shift=0 } }
      }
      local i = 1
      for lo, hi, value in map:iterate_psid_map() do
         local ipv4, expected = unpack(psid_map_iter[i])
         assert(lo == ipv4)
         assert(hi == ipv4)
         assert(value.psid_length == expected.psid_length)
         assert(value.shift == expected.shift)
         i = i + 1
      end
      assert(i == #psid_map_iter + 1)
   end

   print('ok')
end
