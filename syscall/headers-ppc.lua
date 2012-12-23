-- ppc specific definitions

local ffi = require "ffi"

local arch = {}

arch.termio = function()
ffi.cdef[[
static const int NCC = 10;
struct termio {
  unsigned short c_iflag;
  unsigned short c_oflag;
  unsigned short c_cflag;
  unsigned short c_lflag;
  unsigned char c_line;
  unsigned char c_cc[NCC];
};
]]
end

return arch

