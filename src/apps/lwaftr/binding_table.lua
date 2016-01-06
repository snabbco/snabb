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
local BINDING_TABLE_VERSION = 0x00001000
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

local function maybe(f, ...)
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

local function has_magic(stream)
   local res = pcall(read_magic, stream)
   stream:seek(0)
   return res
end

local function is_fresh(stream, mtime_sec, mtime_nsec)
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
   return builder:build()
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
   if #addresses == 0 then parser:error('no lwaftr addresses specified') end
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

   local ipv4_protocol = require("lib.protocol.ipv4")
   local ipv6_protocol = require("lib.protocol.ipv6")
   local function lookup(ipv4, port)
      local ipv4_as_uint = ffi.cast('uint32_t*', ipv4_protocol:pton(ipv4))[0]
      return map:lookup(ffi.C.ntohl(ipv4_as_uint), port)
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
   print('ok')
end
