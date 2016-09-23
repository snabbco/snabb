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
-- an AFTR may have multiple configured addresses.  The address is
-- actually stored as an index into the BR address table, because we
-- have space in the softwire table for a 4-byte index but not a 16-byte
-- IPv6 value.
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
local stream = require("apps.lwaftr.stream")
local lwdebug = require("apps.lwaftr.lwdebug")
local Parser = require("apps.lwaftr.conf_parser").Parser
local rangemap = require("apps.lwaftr.rangemap")
local phm = require("apps.lwaftr.podhashmap")

local band, bor, bxor, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift

local BINDING_TABLE_MAGIC = "\0bindingtabl"
local BINDING_TABLE_VERSION = 0x00002000
local binding_table_header_t = ffi.typeof[[
   struct {
      uint8_t magic[12];
      uint32_t version;
      uint64_t mtime_sec;
      uint32_t mtime_nsec;
   }
]]

local psid_map_value_t = ffi.typeof[[
   struct { uint16_t psid_length; uint16_t shift; }
]]

local br_addresses_header_t = ffi.typeof('struct { uint32_t count; }')
local br_address_t = ffi.typeof('struct { uint8_t addr[16]; }')

-- Total softwire entry size is 32 bytes (with the 4 byte hash), which
-- has nice cache alignment properties.
local softwire_key_t = ffi.typeof[[
   struct {
      uint32_t ipv4;       // Public IPv4 address of this softwire (host-endian).
      uint16_t psid;       // Port set ID.
      uint16_t padding;    // Zeroes.
   } __attribute__((packed))
]]
local softwire_value_t = ffi.typeof[[
   struct {
      uint32_t br;         // Which border router (lwAFTR IPv6 address)?
      uint8_t b4_ipv6[16]; // Address of B4.
   } __attribute__((packed))
]]

local SOFTWIRE_TABLE_LOAD_FACTOR = 0.4

function maybe(f, ...)
   local function catch(success, ...)
      if success then return ... end
   end
   return catch(pcall(f, ...))
end

local function read_magic(stream)
   local header = stream:read_ptr(binding_table_header_t)
   local magic = ffi.string(header.magic, ffi.sizeof(header.magic))
   if magic ~= BINDING_TABLE_MAGIC then
      stream:error('bad magic')
   end
   if header.version ~= BINDING_TABLE_VERSION then
      stream:error('bad version')
   end
end

function has_magic(stream)
   local res = pcall(read_magic, stream)
   stream:seek(0)
   return res
end

function is_fresh(stream, mtime_sec, mtime_nsec)
   local header = stream:read_ptr(binding_table_header_t)
   local res = header.mtime_sec == mtime_sec and header.mtime_nsec == mtime_nsec
   stream:seek(0)
   return res
end

local hash_i32 = phm.hash_i32
local function hash_softwire(key)
   local ipv4, psid = key.ipv4, key.psid
   -- PSID is only 16 bits.  Duplicate the bits into the upper half so
   -- that the hash function isn't spreading around needless zeroes.
   psid = bor(psid, lshift(psid, 16))
   return hash_i32(bxor(ipv4, hash_i32(psid)))
end


BTLookupQueue = {}

-- BTLookupQueue needs a binding table to get softwires, BR addresses
-- and PSID lookup.
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
      self.packet_queue[n] = nil
      if not streamer:is_empty(n) then
         b4_ipv6 = streamer.entries[n].value.b4_ipv6
         br_ipv6 = self.binding_table:get_br_address(streamer.entries[n].value.br)
      end
      return pkt, b4_ipv6, br_ipv6
   end
end

function BTLookupQueue:reset_queue()
   self.length = 0
end

local BindingTable = {}

function BindingTable.new(psid_map, br_addresses, br_address_count,
                          softwires)
   local ret = {
      psid_map = assert(psid_map),
      br_addresses = assert(br_addresses),
      br_address_count = assert(br_address_count),
      softwires = assert(softwires)
   }
   return setmetatable(ret, {__index=BindingTable})
end

local lookup_key = softwire_key_t()
function BindingTable:lookup(ipv4, port)
   local psid = self:lookup_psid(ipv4, port)
   lookup_key.ipv4 = ipv4
   lookup_key.psid = psid
   local res = self.softwires:lookup(lookup_key)
   if res then return self.softwires:val_at(res) end
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

function BindingTable:get_br_address(i)
   assert(i<self.br_address_count)
   return self.br_addresses[i].addr
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

-- Iterate over the BR addresses in a binding table.  Invoke like:
--
--   for ipv6 in bt:iterate_br_addresses() do ... end
--
-- The IPv6 value is a uint8_t[16].
function BindingTable:iterate_br_addresses()
   local idx = -1
   local function next_br_address()
      idx = idx + 1
      if idx >= self.br_address_count then return end
      return self.br_addresses[idx].addr
   end
   return next_br_address
end

-- Iterate over the softwires in a binding table.  Invoke like:
--
--   for entry in bt:iterate_softwires() do ... end
--
-- Each entry is a pointer with two members, "key" and "value".  They
-- key is a softwire_key_t and has "ipv4" and "psid" members.  The value
-- is a softwire_value_t and has "br" and "b4_ipv6" members.  The br is
-- a zero-based index into the br_addresses array, and b4_ipv6 is a
-- uint8_t[16].
function BindingTable:iterate_softwires()
   return self.softwires:iterate()
end

function BindingTable:save(filename, mtime_sec, mtime_nsec)
   local out = stream.open_temporary_output_byte_stream(filename)
   out:write_ptr(binding_table_header_t(
                    BINDING_TABLE_MAGIC, BINDING_TABLE_VERSION,
                    mtime_sec or 0, mtime_nsec or 0))
   self.psid_map:save(out)
   out:write_ptr(br_addresses_header_t(self.br_address_count))
   out:write_array(self.br_addresses, br_address_t, self.br_address_count)
   self.softwires:save(out)
   out:close_and_rename(filename)
end

function BindingTable:dump(filename)
   local tmp = os.tmpname()
   local out = io.open(tmp, 'w+')
   local ipv4, ipv6 = require('lib.protocol.ipv4'), require('lib.protocol.ipv6')
   local function fmt(out, template, ...) out:write(template:format(...)) end
   local function dump(template, ...) fmt(out, template, ...) end

   local function ipv4_ntop(addr)
      return ipv4:ntop(ffi.new('uint32_t[1]', { ffi.C.htonl(addr) }))
   end

   dump("psid_map {\n")
   for lo, hi, psid_info in self:iterate_psid_map() do
      dump("  ")
      if lo < hi then dump('%s-', ipv4_ntop(lo)) end
      dump('%s { psid_length=%d', ipv4_ntop(hi), psid_info.psid_length)
      if psid_info.shift ~= 16 - psid_info.shift then
         dump(', shift=%d', psid_info.shift)
      end
      dump("  }\n")
   end
   dump("}\n\n")

   dump("br_addresses {\n")
   for addr in self:iterate_br_addresses() do
      dump("  %s\n", ipv6:ntop(addr))
   end
   dump("}\n\n")

   dump("softwires {\n")
   for entry in self:iterate_softwires() do
      dump("  { ipv4=%s, psid=%d, b4=%s", ipv4_ntop(entry.key.ipv4),
           entry.key.psid, ipv6:ntop(entry.value.b4_ipv6))
      if entry.value.br ~= 0 then dump(", aftr=%d", entry.value.br) end
      dump(" }\n")
   end
   dump("}\n\n")

   out:flush()

   local res, err = os.rename(tmp, filename)
   if not res then
      io.stderr:write("Failed to rename "..tmp.." to "..filename..": ")
      io.stderr:write(tostring(err).."\n")
   else
      print("Binding table dumped to "..filename..".")
   end
end

local function load_compiled(stream)
   read_magic(stream)
   local psid_map = rangemap.load(stream, psid_map_value_t)
   local br_address_count = stream:read_ptr(br_addresses_header_t).count
   local br_addresses = stream:read_array(br_address_t, br_address_count)
   local softwires = phm.load(stream, softwire_key_t, softwire_value_t,
                              hash_softwire)
   return BindingTable.new(psid_map, br_addresses, br_address_count, softwires)
end

local function parse_psid_map(parser)
   local psid_info_spec = {
      parse={
         psid_length=Parser.parse_psid_param,
         shift=Parser.parse_psid_param
      },
      defaults={
         psid_length=function(config) return 16 - (config.shift or 16) end,
         shift=function(config) return 16 - (config.psid_length or 0) end
      },
      validate=function(parser, config)
         if config.psid_length + config.shift ~= 16 then
            parser:error('psid_length %d + shift %d should add up to 16',
                         config.psid_length, config.shift)
         end
      end
   }

   local builder = rangemap.RangeMapBuilder.new(psid_map_value_t)
   local value = psid_map_value_t()
   parser:skip_whitespace()
   parser:consume_token('[%a_]', 'psid_map')
   parser:skip_whitespace()
   parser:consume('{')
   parser:skip_whitespace()
   while not parser:check('}') do
      local range_list = parser:parse_ipv4_range_list()
      local info = parser:parse_property_list(psid_info_spec, '{', '}')
      value.psid_length, value.shift = info.psid_length, info.shift
      for _, range in ipairs(range_list) do
         builder:add_range(range.min, range.max, value)
      end
      parser:skip_whitespace()
      if parser:check(',') or parser:check(';') then
         parser:skip_whitespace()
      end
   end
   return builder:build(psid_map_value_t())
end

local function parse_br_addresses(parser)
   local addresses = {}
   parser:skip_whitespace()
   parser:consume_token('[%a_]', 'br_addresses')
   parser:skip_whitespace()
   parser:consume('{')
   parser:skip_whitespace()
   while not parser:check('}') do
      table.insert(addresses, parser:parse_ipv6())
      parser:skip_whitespace()
      if parser:check(',') then parser:skip_whitespace() end
   end
   local ret = ffi.new(ffi.typeof('$[?]', br_address_t), #addresses)
   for i, addr in ipairs(addresses) do ret[i-1].addr = addr end
   return ret, #addresses
end

local function parse_softwires(parser, psid_map, br_address_count)
   local function required(key)
      return function(config)
         error('missing required configuration key "'..key..'"')
      end
   end
   local softwire_spec = {
      parse={
         ipv4=Parser.parse_ipv4_as_uint32,
         psid=Parser.parse_psid,
         b4=Parser.parse_ipv6,
         aftr=Parser.parse_non_negative_number
      },
      defaults={
         ipv4=required('ipv4'),
         psid=function(config) return 0 end,
         b4=required('b4'),
         aftr=function(config) return 0 end
      },
      validate=function(parser, config)
         local psid_length = psid_map:lookup(config.ipv4).value.psid_length
         if config.psid >= 2^psid_length then
            parser:error('psid %d out of range for IP', config.psid)
         end
         if config.aftr >= br_address_count then
            parser:error('only %d br addresses are defined', br_address_count)
         end
      end
   }

   local map = phm.PodHashMap.new(softwire_key_t, softwire_value_t,
                                  hash_softwire)
   local key, value = softwire_key_t(), softwire_value_t()
   parser:skip_whitespace()
   parser:consume_token('[%a_]', 'softwires')
   parser:skip_whitespace()
   parser:consume('{')
   parser:skip_whitespace()
   while not parser:check('}') do
      local entry = parser:parse_property_list(softwire_spec, '{', '}')
      key.ipv4, key.psid = entry.ipv4, entry.psid
      value.br, value.b4_ipv6 = entry.aftr, entry.b4
      local success = pcall(map.add, map, key, value)
      if not success then
         parser:error('duplicate softwire for ipv4=%s, psid=%d',
                      lwdebug.format_ipv4(key.ipv4), key.psid)
      end
      parser:skip_whitespace()
      if parser:check(',') then parser:skip_whitespace() end
   end
   map:resize(map.size / SOFTWIRE_TABLE_LOAD_FACTOR)
   return map
end

local function parse_binding_table(parser)
   local psid_map = parse_psid_map(parser)
   local br_addresses, br_address_count = parse_br_addresses(parser)
   local softwires = parse_softwires(parser, psid_map, br_address_count)
   parser:skip_whitespace()
   parser:consume(nil)
   return BindingTable.new(psid_map, br_addresses, br_address_count, softwires)
end

function load_source(text_stream)
   return parse_binding_table(Parser.new(text_stream))
end

local verbose = os.getenv('SNABB_LWAFTR_VERBOSE') or true
local function log(msg, ...)
   if verbose then print(msg:format(...)) end
end

function load(file)
   local source = stream.open_input_byte_stream(file)
   if has_magic(source) then
      log('loading compiled binding table from %s', file)
      return load_compiled(source)
   end

   -- If the file doesn't have the magic, assume it's a source file.
   -- First, see if we compiled it previously and saved a compiled file
   -- in a well-known place.
   local compiled_file = file:gsub("%.txt$", "")..'.o'

   local compiled_stream = maybe(stream.open_input_byte_stream,
                                 compiled_file)
   if compiled_stream then
      if has_magic(compiled_stream) then
         log('loading compiled binding table from %s', compiled_file)
         if is_fresh(compiled_stream, source.mtime_sec, source.mtime_nsec) then
            log('compiled binding table %s is up to date.', compiled_file)
            return load_compiled(compiled_stream)
         end
         log('compiled binding table %s is out of date; recompiling.',
             compiled_file)
      end
      compiled_stream:close()
   end
      
   -- Load and compile it.
   log('loading source binding table from %s', file)
   local bt = load_source(source:as_text_stream())

   -- Save it, if we can.
   local success, err = pcall(bt.save, bt, compiled_file,
                              source.mtime_sec, source.mtime_nsec)
   if not success then
      log('error saving compiled binding table %s: %s', compiled_file, err)
   end

   -- Done.
   return bt
end

function selftest()
   print('selftest: binding_table')
   local function string_file(str)
      local pos = 1
      return {
         read = function(self, n)
            assert(n==1)
            local ret
            if pos <= #str then
               ret = str:sub(pos,pos)
               pos = pos + 1
            end
            return ret
         end,
         close = function(self) str = nil end
      }
   end
   local map = load_source(string_file([[
      psid_map {
        178.79.150.233 {psid_length=16}
        178.79.150.15 {psid_length=4, shift=12}
        178.79.150.2 {psid_length=16}
        178.79.150.3 {psid_length=6}
      }
      br_addresses {
        8:9:a:b:c:d:e:f,
        1E:1:1:1:1:1:1:af,
        1E:2:2:2:2:2:2:af
      }
      softwires {
        { ipv4=178.79.150.233, psid=80, b4=127:2:3:4:5:6:7:128, aftr=0 }
        { ipv4=178.79.150.233, psid=2300, b4=127:11:12:13:14:15:16:128 }
        { ipv4=178.79.150.233, psid=2700, b4=127:11:12:13:14:15:16:128 }
        { ipv4=178.79.150.233, psid=4660, b4=127:11:12:13:14:15:16:128 }
        { ipv4=178.79.150.233, psid=7850, b4=127:11:12:13:14:15:16:128 }
        { ipv4=178.79.150.233, psid=22788, b4=127:11:12:13:14:15:16:128 }
        { ipv4=178.79.150.233, psid=54192, b4=127:11:12:13:14:15:16:128 }
        { ipv4=178.79.150.15, psid=0, b4=127:22:33:44:55:66:77:128 }
        { ipv4=178.79.150.15, psid=1, b4=127:22:33:44:55:66:77:128 }
        { ipv4=178.79.150.2, psid=7850, b4=127:24:35:46:57:68:79:128, aftr=1 }
        { ipv4=178.79.150.3, psid=4, b4=127:14:25:36:47:58:69:128, aftr=2 }
      }
                           ]]))

   local tmp = os.tmpname()
   map:save(tmp)
   map = load(tmp)
   os.remove(tmp)

   local tmp = os.tmpname()
   map:save(tmp)
   map = load(tmp)
   os.remove(tmp)

   local tmp = os.tmpname()
   map:dump(tmp)
   map = load(tmp)
   os.remove(tmp)

   local ipv4_protocol = require("lib.protocol.ipv4")
   local ipv6_protocol = require("lib.protocol.ipv6")
   local function pton_host_uint32(ipv4)
      return ffi.C.ntohl(ffi.cast('uint32_t*', ipv4_protocol:pton(ipv4))[0])
   end
   local function lookup(ipv4, port)
      return map:lookup(pton_host_uint32(ipv4), port)
   end
   local function assert_lookup(ipv4, port, ipv6, br)
      local val = assert(lookup(ipv4, port))
      assert(ffi.C.memcmp(ipv6_protocol:pton(ipv6), val.b4_ipv6, 16) == 0)
      assert(val.br == br)
   end
   assert_lookup('178.79.150.233', 80, '127:2:3:4:5:6:7:128', 0)
   assert(lookup('178.79.150.233', 79) == nil)
   assert(lookup('178.79.150.233', 81) == nil)
   assert_lookup('178.79.150.15', 80, '127:22:33:44:55:66:77:128', 0)
   assert_lookup('178.79.150.15', 4095, '127:22:33:44:55:66:77:128', 0)
   assert_lookup('178.79.150.15', 4096, '127:22:33:44:55:66:77:128', 0)
   assert_lookup('178.79.150.15', 8191, '127:22:33:44:55:66:77:128', 0)
   assert(lookup('178.79.150.15', 8192) == nil)
   assert_lookup('178.79.150.2', 7850, '127:24:35:46:57:68:79:128', 1)
   assert(lookup('178.79.150.3', 4095) == nil)
   assert_lookup('178.79.150.3', 4096, '127:14:25:36:47:58:69:128', 2)
   assert_lookup('178.79.150.3', 5119, '127:14:25:36:47:58:69:128', 2)
   assert(lookup('178.79.150.3', 5120) == nil)
   assert(lookup('178.79.150.4', 7850) == nil)

   do
      local psid_map_iter = {
         { pton_host_uint32('178.79.150.2'), { psid_length=16, shift=0 } },
         { pton_host_uint32('178.79.150.3'), { psid_length=6, shift=10 } },
         { pton_host_uint32('178.79.150.15'), { psid_length=4, shift=12 } },
         { pton_host_uint32('178.79.150.233'), { psid_length=16, shift=0 } }
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

   do
      local br_address_iter = {
         '8:9:a:b:c:d:e:f',
         '1E:1:1:1:1:1:1:af',
         '1E:2:2:2:2:2:2:af'
      }
      local i = 1
      for ipv6 in map:iterate_br_addresses() do
         local expected = ipv6_protocol:pton(br_address_iter[i])
         assert(ffi.C.memcmp(expected, ipv6, 16) == 0)
         i = i + 1
      end
      assert(i == #br_address_iter + 1)
   end

   do
      local i = 0
      for entry in map:iterate_softwires() do i = i + 1 end
      -- 11 softwires in above example.  Since they are hashed into an
      -- arbitrary order, we can't assert much about the iteration.
      assert(i == 11)
   end

   print('ok')
end
