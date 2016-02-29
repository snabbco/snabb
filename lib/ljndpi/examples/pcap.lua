#! /usr/bin/env luajit
--
-- pcap.lua
-- Copyright (C) 2016 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local ffi  = require("ffi")
local pcap = ffi.load("pcap")
local C    = ffi.C

ffi.cdef [[
typedef struct pcap pcap_t;

struct pcap_pkthdr {
   uint64_t ts_sec;   /* timestamp seconds      */
   uint64_t ts_usec;  /* timestamp microseconds */
   uint32_t incl_len; /* number of bytes stored */
   uint32_t orig_len; /* actual packet length   */
};

pcap_t* pcap_open_offline (const char *filename, char *errbuf);
void    pcap_close (pcap_t *);

const uint8_t* pcap_next (pcap_t *p, struct pcap_pkthdr *h);
int pcap_datalink (pcap_t *p);

void free (void*);
]]

local pcap_header = ffi.metatype("struct pcap_pkthdr", {})

local function pcap_close(pcap_handle)
   ffi.gc(pcap_handle, nil)
   pcap.pcap_close(pcap_handle)
end

local pcap_file = ffi.metatype("pcap_t", {
   __new = function (ctype, filename)
      local errbuf = ffi.new("char[512]")
      local pcap_handle = pcap.pcap_open_offline(filename, errbuf)
      if pcap_handle == nil then
         error(ffi.string(errbuf))
      end
      return pcap_handle
   end;

   __gc = pcap_close;

   __index = {
      next = pcap.pcap_next;
      data_link = pcap.pcap_datalink;
      close = function (self)
         ffi.gc(self, nil)
         pcap.pcap_close(self)
      end;
      packets = function (self)
         return coroutine.wrap(function ()
            local header = pcap_header()
            while true do
               local packet = self:next(header)
               if packet == nil then
                  break
               end
               coroutine.yield(header, packet)
            end
         end)
      end;
   };
})

return {
   header = pcap_header;
   file   = pcap_file;

   DLT_NULL      = 0;
   DLT_EN10MB    = 1;
   DLT_RAW       = (ffi.os == "OpenBSD") and 14 or 12;
   DLT_LINUX_SLL = 113;
}
