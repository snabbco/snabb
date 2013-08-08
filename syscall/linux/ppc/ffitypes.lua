-- ppc specific definitions

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local ffi = require "ffi"

local arch = {}

arch.termio = function()
return [[
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

arch.ucontext = function()
return [[
typedef unsigned long greg_t, gregset_t[48];
typedef struct {
  double fpregs[32];
  double fpscr;
  unsigned _pad[2];
} fpregset_t;
typedef struct {
  unsigned vrregs[32][4];
  unsigned vrsave;
  unsigned _pad[2];
  unsigned vscr;
} vrregset_t;
typedef struct {
  gregset_t gregs;
  fpregset_t fpregs;
  vrregset_t vrregs __attribute__((__aligned__(16)));
} mcontext_t;
]]
end

return arch

