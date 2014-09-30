module(...,package.seeall)

local ffi = require("ffi")
local types = require("pf.types")

ffi.cdef[[
int open(const char *pathname, int flags);
int close(int fd);
typedef long int off_t;
off_t lseek(int fd, off_t offset, int whence);
void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
int munmap(void *addr, size_t length);
]]

function open(filename)
   return ffi.C.open(filename, 0)
end

function mmap(fd, size)
   local PROT_READ = 1
   local MAP_PRIVATE = 2
   local ptr = ffi.C.mmap(ffi.cast("void *", 0), size, PROT_READ, MAP_PRIVATE, fd, 0)
   if ptr == ffi.cast("void *", -1) then
      error("Error mmapping")
   end
   return ptr
end

function size(fd)
   local SEEK_SET = 0
   local SEEK_END = 2
   local size = ffi.C.lseek(fd, 0, SEEK_END)
   ffi.C.lseek(fd, 0, SEEK_SET)
   return size
end

function open_and_mmap(filename)
   local fd = open(filename, O_RDONLY)
   if fd == -1 then
      error("Error opening " .. filename)
   end

   local sz = size(fd)
   local ptr = mmap(fd, sz)
   ffi.C.close(fd)

   if ptr == ffi.cast("void *", -1) then
      error("Error mmapping " .. filename)
   end

   ptr = ffi.cast("unsigned char *", ptr)
   local ptr_end = ptr + sz
   local header = ffi.cast("struct pcap_file *", ptr)
   if header.magic_number == 0xD4C3B2A1 then
      error("Endian mismatch in " .. filename)
   elseif header.magic_number ~= 0xA1B2C3D4 then
      error("Bad PCAP magic number in " .. filename)
   end

   return header, ptr + ffi.sizeof("struct pcap_file"), ptr_end
end

function records_mm(filename)
   local fd = open(filename, O_RDONLY)
   if fd == -1 then
      error("Error opening " .. filename)
   end
   local size = size(fd)
   local ptr = mmap(fd, size)
   if ptr == ffi.cast("void *", -1) then
      error("Error mmapping " .. filename)
   end
   if (-1 == ffi.C.close(fd)) then
      error("Error closing fd")
   end
   local start = ptr
   ptr = ffi.cast("unsigned char *", ptr)
   local ptr_end = ptr + size
   local header = ffi.cast("struct pcap_file *", ptr)
   if header.magic_number == 0xD4C3B2A1 then
      error("Endian mismatch in " .. filename)
   elseif header.magic_number ~= 0xA1B2C3D4 then
      error("Bad PCAP magic number in " .. filename)
   end
   ptr = ptr + ffi.sizeof("struct pcap_file")
   local function pcap_records_it()
      if ptr >= ptr_end then
         if (-1 == ffi.C.munmap(start, size)) then
            error("Error munmapping")
         end
         return nil
      end
      local record = ffi.cast("struct pcap_record *", ptr)
      local packet = ffi.cast("unsigned char *", record + 1)
      ptr = packet + record.incl_len
      return packet, record
   end
   return pcap_records_it, true, true
end

function write_file_header(file)
   local pcap_file = ffi.new("struct pcap_file")
   pcap_file.magic_number = 0xa1b2c3d4
   pcap_file.version_major = 2
   pcap_file.version_minor = 4
   pcap_file.snaplen = 65535
   pcap_file.network = 1
   file:write(ffi.string(pcap_file, ffi.sizeof(pcap_file)))
   file:flush()
end

function write_record (file, ffi_buffer, length)
   write_record_header(file, length)
   file:write(ffi.string(ffi_buffer, length))
   file:flush()
end

function write_record_header (file, length)
   local pcap_record = types.pcap_record(0, 0, length, length)
   pcap_record.incl_len = length
   pcap_record.orig_len = length
   file:write(ffi.string(pcap_record, ffi.sizeof(pcap_record)))
end
