-- Address maps
--
-- The lw4o6 architecture supports sharing of IPv4 addresses by
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
-- Source: http://tools.ietf.org/html/rfc7597#section-5.1 
--
-- We find the specification's names to be a bit obtuse, so we refer to
-- them using the following names:
--
--   a bits = reserved_ports_bit_count.
--   k bits = psid_length.
--   m bits = shift.
--
-- Anyway, an address map is a lookup table that, given an IPv4 address
-- and a port, uses the appropriate "psid_length" and "shift" parameters
-- to compute a PSID.  If the IPv4 address is not under control of the
-- lwAFTR, the address map still returns a PSID, under the assumption
-- that the subsequent binding table lookup will fail.  After all, what
-- we're really interested in is mapping a packet to a binding table
-- entry, and computing the PSID is just a detail.
-- 
module(..., package.seeall)

local bit = require("bit")
local ffi = require("ffi")
local S = require("syscall")
local rangemap = require("apps.lwaftr.rangemap")
local Parser = require("apps.lwaftr.conf_parser").Parser

local band, rshift, lshift = bit.band, bit.rshift, bit.lshift

local address_map_value = ffi.typeof([[
   struct { uint16_t psid_length; uint16_t shift; }
]])

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

function parse_address_map(parser)
   local entries = {}
   parser:skip_whitespace()
   while not parser:is_eof() do
      local range_list = parser:parse_ipv4_range_list()
      local info = parser:parse_property_list(psid_info_spec, '{', '}')
      info.range_list = range_list
      table.insert(entries, info)
      parser:skip_whitespace()
   end
   return entries
end

local function parse(stream)
   return parse_address_map(Parser.new(stream))
end

local function attach_lookup_helper(map)
   local function port_to_psid(port, psid_length, shift)
      local psid_mask = lshift(1, psid_length)-1
      local psid = band(rshift(port, shift), psid_mask)
      -- Are there are restricted ports for this address?
      if psid_length + shift < 16 then
         local reserved_ports_bit_count = 16 - psid_length - shift
         local first_allocated_port = lshift(1, reserved_ports_bit_count)
         -- The port is within the range of restricted ports.  Assign a
         -- bogus PSID so that lookup will fail.
         if port < first_allocated_port then psid = psid_mask + 1 end
      end
      return psid
   end

   function map:lookup_psid(ipv4, port)
      local psid_info = self:lookup(ipv4).value
      local psid_length, shift = psid_info.psid_length, psid_info.shift
      return port_to_psid(port, psid_length, shift)
   end
   return map
end

function compile(file)
   local parser = Parser.new(file)
   local builder = rangemap.RangeMapBuilder.new(address_map_value,
                                                parser.mtime_sec,
                                                parser.mtime_nsec)
   local value = address_map_value()
   for _, entry in ipairs(parse_address_map(parser)) do
      value.psid_length = entry.psid_length
      value.shift = entry.shift
      for _, range in ipairs(entry.range_list) do
         builder:add_range(range.min, range.max, value)
      end
   end
   return attach_lookup_helper(builder:build())
end

local verbose = os.getenv('SNABB_LWAFTR_VERBOSE')
local function log(msg, ...)
   if verbose then print(msg:format(...)) end
end

function load(file)
   local RangeMap = rangemap.RangeMap
   if RangeMap.has_magic(file) then
      log('loading compiled address map from %s', file)
      return attach_lookup_helper(RangeMap.load(file, address_map_value))
   end

   -- If the file doesn't have the magic, assume it's a source file.
   -- First, see if we compiled it previously and saved a compiled file
   -- in a well-known place.
   local compiled = file:gsub("%.txt$", "")..'.map'
   if RangeMap.has_magic(compiled) then
      log('loading compiled address map from %s', compiled)
      local map = attach_lookup_helper(RangeMap.load(compiled, address_map_value))
      local stat = S.stat(file)
      if (map.mtime_sec == stat.st_mtime and
          map.mtime_nsec == stat.st_mtime_nsec) then
         -- The compiled file is fresh.
         log('compiled address map %s is up to date.', compiled)
         return map
      end
      log('compiled address map %s is out of date; recompiling.', compiled)
   end

   -- Load and compile it.
   log('loading source address map from %s', file)
   local map = compile(file)

   -- Save it, if we can.
   local success, err = pcall(save, map, compiled)
   if not success then
      log('error saving compiled address map %s: %s', compiled, err)
   end

   -- Done.
   return map
end

local function mktemp(name, mode)
   if not mode then mode = "rusr, wusr, rgrp, roth" end
   local t = math.random(1e7)
   local tmpnam, fd, err
   for i = t, t+10 do
      tmpnam = name .. '.' .. i
      fd, err = S.open(tmpnam, "creat, wronly, excl", mode)
      if fd then
         fd:close()
         return tmpnam, nil
      end
      i = i + 1
   end
   return nil, err
end

function save(map, file)
   local tmp_file, err = mktemp(file)
   if not tmp_file then
      local dir = ffi.string(ffi.C.dirname(file))
      error("failed to create temporary file in "..dir..": "..err)
   end
   map:save(tmp_file)
   local res, err = S.rename(tmp_file, file)
   if not res then
      error("failed to rename "..tmp_file.." to "..file..": "..err)
   end
end

function selftest()
   print('selftest: address_map')
   local assert_equals = require('pf.utils').assert_equals
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
   local function parse_string(str) return parse(string_file(str)) end
   local function test(str, expected)
      assert_equals(parse_string(str), expected)
      if str ~= '' then compile(string_file(str)) end
   end
   test('', {})
   test('1.0.0.0{}',
        {{range_list={{min=2^24,max=2^24}}, psid_length=0, shift=16}})
   test('1.0.0.0 {psid_length=10}',
        {{range_list={{min=2^24,max=2^24}}, psid_length=10, shift=6}})
   test('1.0.0.0 {shift=6}',
        {{range_list={{min=2^24,max=2^24}}, psid_length=10, shift=6}})
   test('1.0.0.0 {shift=7,psid_length=9}',
        {{range_list={{min=2^24,max=2^24}}, psid_length=9, shift=7}})
   test('1.0.0.0 {psid_length=7,shift=9}',
        {{range_list={{min=2^24,max=2^24}}, psid_length=7, shift=9}})
   test([[
            1.0.0.0-1.255.255.255 {psid_length=7,shift=9}
            2.0.0.0,2.0.0.1 {}
        ]],
        {{range_list={{min=2^24,max=2^25-1}}, psid_length=7, shift=9},
         {range_list={{min=2^25,max=2^25}, {min=2^25+1,max=2^25+1}},
          psid_length=0, shift=16}})
   print('ok')
end
