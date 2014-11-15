module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C

local filter = subClass(nil)
filter._name = "pcap packet filter"

-- Create a filter with an arbitrary libpcap filter expression
function filter:new(program)
   local o = filter:superClass().new(self)
   if _G.pflua then
      -- Include pflua
      package.path = package.path .. ";../deps/pflua/src/?.lua"
      local pflua = require("pf")

      -- Compile filter
      local opts = { }
      o._filter = pflua.compile_filter(program, opts)
   else
      -- Include headers
      require ("lib.pcap.filter_h")
      ffi.load("pcap", true)

      -- Dummy pcap handle shared by all instances. Link type 1 corresponds to
      -- Ethernet
      local pcap = C.pcap_open_dead(1, 0xffff)

      -- Compile filter
      o._bpf = ffi.new("struct bpf_program")
      if C.pcap_compile(pcap, o._bpf, ffi.cast("char *", program), 1, 0xffffffff) ~= 0 then
         o:free()
         return nil, C.pcap_geterr(pcap)
      end
      o._header = ffi.new("struct pcap_pkthdr")
   end
   return o
end

-- Apply the filter to a region of memory
function filter:match(data, length)
   if _G.pflua then
      return self._filter(data, length)
   else
      local header = self._header
      header.incl_len = length
      header.orig_len = length
      return C.pcap_offline_filter(self._bpf, header, ffi.cast("char *", data)) ~= 0
   end
end

return filter
