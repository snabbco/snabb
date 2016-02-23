module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
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
   return C.open(filename, 0)
end

function mmap(fd, size)
   local PROT_READ = 1
   local MAP_PRIVATE = 2
   local ptr = C.mmap(ffi.cast("void *", 0), size, PROT_READ, MAP_PRIVATE, fd, 0)
   if ptr == ffi.cast("void *", -1) then
      error("Error mmapping")
   end
   return ptr
end

function size(fd)
   local SEEK_SET = 0
   local SEEK_END = 2
   local size = C.lseek(fd, 0, SEEK_END)
   C.lseek(fd, 0, SEEK_SET)
   return size
end

function open_and_mmap(filename)
   local fd = open(filename, O_RDONLY)
   if fd == -1 then
      error("Error opening " .. filename)
   end

   local sz = size(fd)
   local ptr = mmap(fd, sz)
   C.close(fd)

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

function load_packets(filename)
   local _, ptr, ptr_end = open_and_mmap(filename)
   local ret = {}
   local i = 1
   while ptr < ptr_end do
      local record = ffi.cast("struct pcap_record *", ptr)
      local packet = ffi.cast("unsigned char *", record + 1)
      ret[i] = { packet=packet, len=record.incl_len }
      i = i + 1
      ptr = packet + record.incl_len
   end
   return ret
end
