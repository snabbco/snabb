-- If using Linux ABI compatibility we need a few extra types from NetBSD
-- TODO In theory we should not need these, just create a new NetBSD rump instance when we want them instead

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local function init(types, hh, abi, c)

local ffi = require "ffi"

ffi.cdef [[
typedef uint32_t _netbsd_mode_t;
typedef uint64_t _netbsd_ino_t;
typedef uint8_t _netbsd_sa_family_t;
struct _netbsd_sockaddr {
  uint8_t       sa_len;
  _netbsd_sa_family_t   sa_family;
  char          sa_data[14];
};
struct _netbsd_sockaddr_storage {
  uint8_t       ss_len;
  _netbsd_sa_family_t   ss_family;
  char          __ss_pad1[6];
  int64_t       __ss_align;
  char          __ss_pad2[128 - 2 - 8 - 6];
};
struct _netbsd_ufs_args {
  char *fspec;
};
struct _netbsd_tmpfs_args {
  int ta_version;
  _netbsd_ino_t ta_nodes_max;
  off_t ta_size_max;
  uid_t ta_root_uid;
  gid_t ta_root_gid;
  _netbsd_mode_t ta_root_mode;
};
struct _netbsd_ptyfs_args {
  int version;
  gid_t gid;
  _netbsd_mode_t mode;
  int flags;
};
struct _netbsd_compat_60_ptmget {
  int     cfd;
  int     sfd;
  char    cn[16];
  char    sn[16];
};
struct _netbsd_ptmget {
  int     cfd;
  int     sfd;
  char    cn[1024];
  char    sn[1024];
};
struct _netbsd_ifreq {
  char ifr_name[16];
  union {
    struct  _netbsd_sockaddr ifru_addr;
    struct  _netbsd_sockaddr ifru_dstaddr;
    struct  _netbsd_sockaddr ifru_broadaddr;
    struct  _netbsd_sockaddr_storage ifru_space;
    short   ifru_flags;
    int     ifru_metric;
    int     ifru_mtu;
    int     ifru_dlt;
    unsigned int   ifru_value;
    void *  ifru_data;
    struct {
      uint32_t        b_buflen;
      void            *b_buf;
    } ifru_b;
  } ifr_ifru;
};
struct _netbsd_ifaliasreq {
  char    ifra_name[16];
  struct  _netbsd_sockaddr ifra_addr;
  struct  _netbsd_sockaddr ifra_dstaddr;
  struct  _netbsd_sockaddr ifra_mask;
};
]]

local t, pt, s, ctypes = types.t, types.pt, types.s, types.ctypes

local ptt, addtype, lenfn, lenmt, newfn, istype = hh.ptt, hh.addtype, hh.lenfn, hh.lenmt, hh.newfn, hh.istype

local ffi = require "ffi"
local bit = require "bit"

local h = require "syscall.helpers"

local ntohl, ntohl, ntohs, htons = h.ntohl, h.ntohl, h.ntohs, h.htons

local mt = {} -- metatables

local addtypes = {
}

local addstructs = {
  ufs_args = "struct _netbsd_ufs_args",
  tmpfs_args = "struct _netbsd_tmpfs_args",
  ptyfs_args = "struct _netbsd_ptyfs_args",
}

if abi.netbsd.version == 6 then
  addstructs.ptmget = "struct _netbsd_compat_60_ptmget"
else
  addstructs.ptmget = "struct _netbsd_ptmget"
end

for k, v in pairs(addtypes) do addtype(k, v) end
for k, v in pairs(addstructs) do addtype(k, v, lenmt) end

return types

end

return {init = init}

