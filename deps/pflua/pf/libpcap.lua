module(...,package.seeall)

local ffi = require("ffi")
local types = require("pf.types") -- Load FFI declarations.
local pcap -- The pcap library, lazily loaded.

verbose = os.getenv("PF_VERBOSE");

local MAX_UINT32 = 0xffffffff

ffi.cdef[[
typedef struct pcap pcap_t;
int pcap_datalink_name_to_val(const char *name);
pcap_t *pcap_open_dead(int linktype, int snaplen);
void pcap_perror(pcap_t *p, const char *suffix);
int pcap_compile(pcap_t *p, struct bpf_program *fp, const char *str,
                 int optimize, uint32_t netmask);
int pcap_offline_filter(const struct bpf_program *fp,
                        const struct pcap_pkthdr *h, const uint8_t *pkt);
]]

function offline_filter(bpf, hdr, pkt)
   return pcap.pcap_offline_filter(bpf, hdr, pkt)
end

-- The dlt_name is a "datalink type name" and specifies the link-level
-- wrapping to expect.  E.g., for raw ethernet frames, you would specify
-- "EN10MB" (even though you have a 10G card), which corresponds to the
-- numeric DLT_EN10MB value from pcap/bpf.h.  See
-- http://www.tcpdump.org/linktypes.html for more details on possible
-- names.
--
-- You probably want "RAW" for raw IP (v4 or v6) frames.  If you don't
-- supply a dlt_name, "RAW" is the default.
function compile(filter_str, dlt_name)
   if verbose then print(filter_str) end
   if not pcap then pcap = ffi.load("pcap") end

   dlt_name = dlt_name or "RAW"
   local dlt = pcap.pcap_datalink_name_to_val(dlt_name)
   assert(dlt >= 0, "bad datalink type name " .. dlt_name)
   local snaplen = 65535 -- Maximum packet size.
   local p = pcap.pcap_open_dead(dlt, snaplen)

   assert(p, "pcap_open_dead failed")

   -- pcap_compile
   local bpf = types.bpf_program()
   local optimize = true
   local netmask = MAX_UINT32
   local err = pcap.pcap_compile(p, bpf, filter_str, optimize, netmask)

   if err ~= 0 then
      pcap.pcap_perror(p, "pcap_compile failed!")
      error("pcap_compile failed")
   end

   return bpf
end

function selftest ()
   print("selftest: pf.libpcap")

   compile("", "EN10MB")
   compile("ip", "EN10MB")
   compile("tcp", "EN10MB")
   compile("tcp port 80", "EN10MB")

   print("OK")
end
