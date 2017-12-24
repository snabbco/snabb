-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local ipv4 = require("lib.protocol.ipv4")
local lib = require("core.lib")
local header = require("lib.protocol.header")

local ffi = require("ffi")
local C = ffi.C

ffi.cdef[[
size_t strlen(const char *s);
]]

local htons, ntohs = lib.htons, lib.ntohs
local htonl, ntohl = lib.htonl, lib.ntohl

A   = 0x01
PTR = 0x0c
SRV = 0x21
TXT = 0x10

CLASS_IN = 0x1

local function r16 (ptr)
   return ffi.cast("uint16_t*", ptr)[0]
end
local function contains (t, e)
   for _, each in ipairs(t) do
      if each == e then return true end
   end
   return false
end

DNS = {}

local function encode_name_string (str)
   local function repetitions (str, char)
      local ret = 0
      for each in str:gmatch(char) do
         ret = ret + 1
      end
      return ret
   end
   local extra = repetitions(str, '%.') + 1
   local ret = ffi.new("char[?]", #str + extra + 1)
   local buffer = ret
   local function write_len (num)
      buffer[0] = num
      buffer = buffer + 1
   end
   local function write_str (arg)
      ffi.copy(buffer, arg, #arg)
      buffer = buffer + #arg
   end
   local total_length = 0
   for each in str:gmatch('([^%.]+)') do
      write_len(#each)
      write_str(each)
      total_length = #each + 1
   end
   return ret, total_length
end

local function decode_name_string (cdata)
   local t = {}
   local buffer, i = cdata, 0
   local function read_len ()
      local len = tonumber(buffer[0])
      buffer = buffer + 1
      return len
   end
   local function read_str (len)
      table.insert(t, ffi.string(buffer, len))
      buffer = buffer + len
   end
   local function eol ()
      return buffer[0] == 0
   end
   local function flush ()
      return table.concat(t, ".")
   end
   while not eol() do
      local len = read_len()
      if len < 0 then break end
      read_str(len)
   end
   return flush()
end

local function encode_string (str)
   assert(type(str) == "string")
   local ret = ffi.new("char[?]", #str+1)
   ret[0] = #str
   ffi.copy(ret + 1, str)
   return ret
end

local function encode_strings (t)
   assert(type(t) == "table")
   local ret = ffi.new("char*[?]", #t)
   for i, each in ipairs(arg) do
      ret[i-1] = encode_single(each)
   end
   return ret
end

local function decode_string (cstr, cstr_len)
   local t = {}
   local pos = 0
   while pos < cstr_len do
      local len = tonumber(cstr[pos])
      pos = pos + 1
      table.insert(t, ffi.string(cstr + pos, len))
      pos = pos + len
   end
   return t
end

-- DNS Query Record.

query_record = subClass(header)
query_record._name = "query_record"
query_record:init({
   [1] = ffi.typeof[[
   struct {
      char* name;
      uint16_t type;
      uint16_t class;
   } __attribute__((packed))
   ]]
})

function query_record:new_from_mem (data, length)
   local o = query_record:superClass().new(self)
   local name, len = parse_name(data, length)
   local h = o:header()
   h.name = name
   h.type = r16(data + len)
   h.class = r16(data + len + 2)
   return o, len + 4
end

function parse_name (data, size)
   local len = 2
   local maybe_type = r16(data + len)
   if maybe_type ~= htons(TXT) then
      len = name_length(data, size)
   end
   if len then
      local name = ffi.new("uint8_t[?]", len)
      ffi.copy(name, data, len)
      return name, len
   end
end

-- Returns dns_record.name's length.
function name_length (data, size)
   local ptr = data
   local i = 0
   while i < size do
      -- PTR records's name end with an end-of-string character. Next byte
      -- belongs to type.
      if ptr[i] == 0 and ptr[i + 1] == 0 then i = i + 1 break end
      -- This zero belongs to type so break.
      if ptr[i] == 0 then break end
      i = i + 1
   end
   return i < size and i or nil
end

function query_record:new (config)
   local o = query_record:superClass().new(self)
   o:name(config.name)
   o:type(config.type)
   o:klass(config.class)
   return o
end

function query_record:name (name)
   local h = self:header()
   if name then
      h.name, len = encode_name_string(name)
   end
   return h.name ~= nil and decode_name_string(h.name) or ""
end

function query_record:type (type)
   if type then
      self:header().type = htons(type)
   end
   return ntohs(self:header().type)
end

function query_record:klass (class)
   if class then
      self:header().class = htons(class)
   end
   return ntohs(self:header().class)
end

-- Size of record depends of length of name.
function query_record:sizeof ()
   local success, h = pcall(self.header, self)
   if not success then
      return self:superClass().sizeof(self)
   else
      return tonumber(C.strlen(h.name) + 1) + 4
   end
end

-- DNS Response Record common fields.
-- Abstract class. Used by all other types of records: A, PTR, SRV and TXT.

local dns_record_header_typedef = [[
   struct {
      char *name;
      uint16_t type;
      uint16_t class;
      uint32_t ttl;
      uint16_t data_length;
   } __attribute__((packed))
]]

local dns_record_header = subClass(header)
dns_record_header._name = "dns_record_header"

function dns_record_header:initialize(o, config)
   o:name(config.name)
   o:klass(config.class)
   o:ttl(config.ttl)
   o:data_length(config.data_length)
end

function dns_record_header:new_from_mem(header, data, size)
   -- Copy name.
   local name, len = parse_name(data, size)
   header.name = name

   -- Cast a temporary pointer for the rest of dns_record_header fields.
   local dns_record_subheader_t = ffi.typeof[[
   struct {
      uint16_t type;
      uint16_t class;
      uint32_t ttl;
      uint16_t data_length;
   } __attribute__((packed))
   ]]
   local dns_record_subheader_ptr_t = ffi.typeof("$*", dns_record_subheader_t)
   local ptr = ffi.cast(dns_record_subheader_ptr_t, data + len)

   header.type = ptr.type
   header.class = ptr.class
   header.ttl = ptr.ttl
   header.data_length = ptr.data_length

   return len + ffi.sizeof(dns_record_subheader_t)
end

function dns_record_header:name (name)
   local h = self:header()
   if name then
      h.name = ffi.new("char[?]", #name)
      ffi.copy(h.name, name)
   end
   return h.name ~= nil and ffi.string(h.name) or ""
end

function dns_record_header:type (type)
   if type then
      self:header().type = htons(type)
   end
   return ntohs(self:header().type)
end

-- TODO: Cannot call method 'class' because it is already defined probably in
-- the parent class).
function dns_record_header:klass (class)
   if class then
      self:header().class = htons(class)
   end
   return ntohs(self:header().class)
end

function dns_record_header:ttl(ttl)
   if ttl then
      self:header().ttl = htonl(ttl)
   end
   return ntohl(self:header().ttl)
end

function dns_record_header:data_length(data_length)
   if data_length then
      self:header().data_length = htons(data_length)
   end
   return ntohs(self:header().data_length)
end

-- TXT record.

txt_record = subClass(dns_record_header)
txt_record._name = "txt_record"
txt_record:init({
   [1] = ffi.typeof(([[
   struct {
      %s;
      char* chunks;
   } __attribute__((packed))
   ]]):format(dns_record_header_typedef))
})

function txt_record:new_from_mem(data, size)
   local o = txt_record:superClass().new(self)
   local offset = dns_record_header:new_from_mem(o:header(), data, size)
   o:header().chunks = ffi.new("char[?]", o:data_length())
   ffi.copy(o:header().chunks, data + offset, o:data_length())
   local total_length = offset + o:data_length()
   return o, total_length
end

function txt_record:new (config)
   local o = txt_record:superClass().new(self)
   dns_record_header:initialize(o, config)
   o:type(TXT)
   if config.chunks then
      o:chunks(config.chunks)
   end
end

function txt_record:chunks (chunks)
   if chunks then
      self:header().chunks = encode_string(chunks)
   end
   return decode_string(self:header().chunks, self:data_length())
end

function txt_record:tostring ()
   local t = decode_string(self:header().chunks, self:data_length())
   return ("{%s}"):format(table.concat(t, ";"))
end

-- SRV record.

srv_record = subClass(dns_record_header)
srv_record._name = "srv_record"
srv_record:init({
   [1] = ffi.typeof(([[
   struct {
      %s;
      uint16_t priority;
      uint16_t weight;
      uint16_t port;
      char* target;
   } __attribute__((packed))
   ]]):format(dns_record_header_typedef))
})

function srv_record:new_from_mem(data, size)
   local o = srv_record:superClass().new(self)
   local offset = dns_record_header:new_from_mem(o:header(), data, size)
   o:header().priority = r16(data + offset)
   o:header().weight = r16(data + offset + 2)
   o:header().port = r16(data + offset + 4)
   o:header().target = ffi.new("char[?]", o:data_length() - 6)
   ffi.copy(o:header().target, data + offset + 6, o:data_length() - 6)
   local total_length = offset + o:data_length()
   return o, total_length
end

function srv_record:new (config)
   local o = srv_record:superClass().new(self)
   o:type(SRV)
   o:priority(config.priority or 0)
   o:weight(config.weight)
   o:port(config.port)
   o:target(config.target)
   return o
end

function srv_record:priority (priority)
   if priority then
      self:header().priority = htons(priority)
   end
   return ntohs(self:header().priority)
end

function srv_record:weight (weight)
   if weight then
      self:header().weight = htons(weight)
   end
   return ntohs(self:header().weight)
end

function srv_record:port (port)
   if port then
      self:header().port = htons(port)
   end
   return ntohs(self:header().port)
end

function srv_record:target (target)
   local h = self:header()
   if target then
      h.target = ffi.new("char[?]", #target)
      ffi.copy(h.target, target)
   end
   return h.target ~= nil and ffi.string(h.target) or ""
end

function srv_record:tostring ()
   local target = decode_name_string(self:header().target)
   return ("{target: %s; port: %d}"):format(target, self:port())
end

-- PTR record.

ptr_record = subClass(dns_record_header)
ptr_record._name = "ptr_record"
ptr_record:init({
   [1] = ffi.typeof(([[
   struct {
      %s;                     /* DNS record header */
      char* domain_name;      /* PTR record own fields */
   } __attribute__((packed))
   ]]):format(dns_record_header_typedef))
})

function ptr_record:new_from_mem(data, size)
   local o = ptr_record:superClass().new(self)
   local offset = dns_record_header:new_from_mem(o:header(), data, size)
   o:header().domain_name = ffi.new("char[?]", o:data_length())
   ffi.copy(o:header().domain_name, data + offset, o:data_length())
   local total_length = offset + o:data_length()
   return o, total_length
end

function ptr_record:new (config)
   local o = ptr_record:superClass().new(self)
   dns_record_header:initialize(o, config)
   o:type(PTR)
   o:domain_name(config.domain_name)
   return o
end

function ptr_record:domain_name (domain_name)
   local h = self:header()
   if domain_name then
      h.domain_name = ffi.new("char[?]", #domain_name)
      ffi.copy(h.domain_name, domain_name)
   end
   return h.domain_name ~= nil and ffi.string(h.domain_name) or ""
end

function ptr_record:tostring ()
   local name = decode_name_string(self:header().name)
   local domain_name = decode_name_string(self:header().domain_name)
   if #name > 0 then
      return ("{name: %s; domain_name: %s}"):format(name, domain_name)
   else
      return ("{domain_name: %s}"):format(domain_name)
   end
end

-- A record.

local a_record = subClass(dns_record_header)
a_record._name = "address_record"
a_record:init({
   [1] = ffi.typeof(([[
   struct {
      %s;                     /* DNS record header */
      uint8_t address[4];     /* A record own fields */
   } __attribute__((packed))
   ]]):format(dns_record_header_typedef))
})

function a_record:new_from_mem(data, size)
   local o = a_record:superClass().new(self)
   local offset = dns_record_header:new_from_mem(o:header(), data, size)
   ffi.copy(o:header().address, data + offset, o:data_length())
   local total_length = offset + o:data_length()
   return o, total_length
end

function a_record:new (config)
   local o = a_record:superClass().new(self)
   dns_record_header:initialize(o, config)
   o:type(A)
   o:address(config.address)
   return o
end

function a_record:address (address)
   if address then
      ffi.copy(self:header().address, ipv4:pton(address), 4)
   end
   return ipv4:ntop(self:header().address)
end

function a_record:tostring ()
   local name = decode_name_string(self:header().name)
   if #name > 0 then
      return ("{name: %s; address: %s}"):format(name, self:address())
   else
      return ("{address: %s}"):format(self:address())
   end
end

function DNS.parse_records (data, size, n)
   n = n or 1
   assert(n >= 0)
   local rrs, total_len = {}, 0
   local ptr = data
   for _=1,n do
      local rr, len = DNS.parse_record(ptr, size)
      if len == 0 then break end
      ptr = ptr + len
      total_len = total_len + len
      table.insert(rrs, rr)
   end
   return rrs, total_len
end

function DNS.parse_record (data, size)
   local function is_supported (type)
      local supported_types = {A, PTR, SRV, TXT}
      return type and contains(supported_types, type)
   end
   local type = parse_type(data, size)
   type = ntohs(assert(type))
   if not is_supported(type) then return nil, 0 end
   return DNS.create_record_by_type(type, data, size)
end

function parse_type (data, size)
   local maybe_type = r16(data + 2)
   if maybe_type == htons(TXT) then
      return maybe_type
   else
      local len = name_length(data, size)
      if len then
         return r16(data + len)
      end
   end
end

function DNS.create_record_by_type (type, data, size)
   if type == A then
      return a_record:new_from_mem(data, size)
   elseif type == PTR then
      return ptr_record:new_from_mem(data, size)
   elseif type == SRV then
      return srv_record:new_from_mem(data, size)
   elseif type == TXT then
      return txt_record:new_from_mem(data, size)
   end
end

function selftest ()
   -- Test PTR record.
   local pkt = packet.from_string(lib.hexundump([[
      09 5f 73 65 72 76 69 63 65 73 07 5f 64 6e 73 2d
      73 64 04 5f 75 64 70 05 6c 6f 63 61 6c 00 00 0c
      00 01 00 00 0e 0f 00 18 10 5f 73 70 6f 74 69 66
      79 2d 63 6f 6e 6e 65 63 74 04 5f 74 63 70 c0 23
   ]], 64))
   local ptr_rr, len = ptr_record:new_from_mem(pkt.data, 64)
   assert(ptr_rr:type() == PTR)
   assert(ptr_rr:ttl() == 3599)
   assert(ptr_rr:klass() == 0x1)
   assert(ptr_rr:data_length() == 24)
   assert(len == 64)

   -- Test A record.
   pkt = packet.from_string(lib.hexundump([[
      14 61 6d 61 7a 6f 6e 2d 32 39 64 36 39 35 38 31
      65 2d 6c 61 6e c0 23 00 01 80 01 00 00 0e 0f 00
      04 c0 a8 56 37
   ]], 37))
   local address_rr, len = a_record:new_from_mem(pkt.data, 37)
   assert(address_rr:type() == A)
   assert(address_rr:ttl() == 3599)
   assert(address_rr:klass() == 0x8001)
   assert(address_rr:data_length() == 4)
   assert(address_rr:address() == "192.168.86.55")
   assert(len == 37)

   -- Test SRV record.
   pkt = packet.from_string(lib.hexundump([[
      3c 61 6d 7a 6e 2e 64 6d 67 72 3a 31 32 31 31 34
      43 39 35 32 43 36 36 39 31 46 39 30 35 43 45 30
      45 35 39 43 45 36 34 31 45 39 38 3a 72 50 50 4b
      75 54 44 79 49 45 3a 36 38 31 32 37 37 0b 5f 61
      6d 7a 6e 2d 77 70 6c 61 79 c0 45 00 21 80 01 00
      00 0e 0f 00 08 00 00 00 00 b9 46 c0 4c
   ]], 93))
   local srv_rr, len = srv_record:new_from_mem(pkt.data, 93)
   assert(srv_rr:type() == SRV)
   assert(srv_rr:ttl() == 3599)
   assert(srv_rr:klass() == 0x8001)
   assert(srv_rr:data_length() == 8)
   assert(srv_rr:priority() == 0)
   assert(srv_rr:weight() == 0)
   assert(srv_rr:port() == 47430)
   assert(len == 93)

   -- Test TXT record.
   pkt = packet.from_string(lib.hexundump([[
      c0 71 00 10 80 01 00 00 0e 0f 00 91 03 73 3d 30
      0f 61 74 3d 6b 37 59 79 41 70 53 54 68 43 48 4a
      17 6e 3d 61 65 69 6f 75 61 65 69 6f 75 61 65 69
      6f 75 61 65 69 6f 75 61 06 74 72 3d 74 63 70 08
      73 70 3d 34 32 31 37 38 04 70 76 3d 31 04 6d 76
      3d 32 03 76 3d 32 03 61 3d 30 22 75 3d 31 32 31
      31 34 43 39 35 32 43 36 36 39 31 46 39 30 35 43
      45 30 45 35 39 43 45 36 34 31 45 39 38 11 61 64
      3d 41 32 4c 57 41 52 55 47 4a 4c 42 59 45 57 05
      64 70 76 3d 31 03 74 3d 38 03 66 3d 30
   ]], 157))
   local txt_rr, len = txt_record:new_from_mem(pkt.data, 157)
   assert(txt_rr:type() == TXT)
   assert(txt_rr:ttl() == 3599)
   assert(txt_rr:klass() == 0x8001)
   assert(txt_rr:data_length() == 145)
   assert(#txt_rr:chunks() == 14)
   assert(len == 157)

   -- MDNS response body containing many records.
   local answers = packet.from_string(lib.hexundump([[
      09 5f 73 65 72 76 69 63 65 73 07 5f 64 6e 73 2d
      73 64 04 5f 75 64 70 05 6c 6f 63 61 6c 00 00 0c
      00 01 00 00 0e 0f 00 18 10 5f 73 70 6f 74 69 66
      79 2d 63 6f 6e 6e 65 63 74 04 5f 74 63 70 c0 23
      14 61 6d 61 7a 6f 6e 2d 32 39 64 36 39 35 38 31
      65 2d 6c 61 6e c0 23 00 01 80 01 00 00 0e 0f 00
      04 c0 a8 56 37 3c 61 6d 7a 6e 2e 64 6d 67 72 3a
      31 32 31 31 34 43 39 35 32 43 36 36 39 31 46 39
      30 35 43 45 30 45 35 39 43 45 36 34 31 45 39 38
      3a 72 50 50 4b 75 54 44 79 49 45 3a 36 38 31 32
      37 37 0b 5f 61 6d 7a 6e 2d 77 70 6c 61 79 c0 45
      00 21 80 01 00 00 0e 0f 00 08 00 00 00 00 b9 46
      c0 4c c0 71 00 10 80 01 00 00 0e 0f 00 91 03 73
      3d 30 0f 61 74 3d 6b 37 59 79 41 70 53 54 68 43
      48 4a 17 61 65 69 6f 75 61 65 69 6f 75 61 65 69
      6f 75 61 65 69 6f 75 61 65 69 06 74 72 3d 74 63
      70 08 73 70 3d 34 32 31 37 38 04 70 76 3d 31 04
      6d 76 3d 32 03 76 3d 32 03 61 3d 30 22 75 3d 31
      32 31 31 34 43 39 35 32 43 36 36 39 31 46 39 30
      35 43 45 30 45 35 39 43 45 36 34 31 45 39 38 11
      61 64 3d 41 32 4c 57 41 52 55 47 4a 4c 42 59 45
      57 05 64 70 76 3d 31 03 74 3d 38 03 66 3d 30
   ]], 351))
   local rrs, total_length = DNS.parse_records(answers.data, 351, 4)
   assert(#rrs == 4)
   assert(total_length == 351)

   -- DNS query record.
   local pkt = packet.from_string(lib.hexundump([[
      0b 5f 67 6f 6f 67 6c 65 7a 6f 6e 65 04 5f 74 63
      70 05 6c 6f 63 61 6c 00 00 0c 00 01
   ]], 28))
   local query_rr, len = query_record:new_from_mem(pkt.data, 28)
   assert(query_rr:name() == "_googlezone._tcp.local")
   assert(query_rr:type() == PTR)
   assert(query_rr:klass() == 0x1)
   assert(query_rr:sizeof() == len)
   assert(query_record:sizeof() == 12)

   local query = "_services._dns-sd._udp.local"
   assert(decode_name_string((encode_name_string(query))) == query)
end
