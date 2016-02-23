-- ffi type and function definitions for rump kernel functions

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local cdef = require "ffi".cdef

cdef[[
typedef struct modinfo {
  unsigned int    mi_version;
  int             mi_class;
  int             (*mi_modcmd)(int, void *);
  const char      *mi_name;
  const char      *mi_required;
} const modinfo_t;

int     rump_boot_gethowto(void);
void    rump_boot_sethowto(int);
void    rump_boot_setsigmodel(int);
void    rump_schedule(void);
void    rump_unschedule(void);
void    rump_printevcnts(void);
int     rump_daemonize_begin(void);
int     rump_daemonize_done(int);
int     rump_init(void);
int     rump_init_server(const char *);

int rump_pub_getversion(void);
int rump_pub_module_init(const struct modinfo * const *, size_t);
int rump_pub_module_fini(const struct modinfo *);
int rump_pub_kernelfsym_load(void *, uint64_t, char *, uint64_t);
struct uio * rump_pub_uio_setup(void *, size_t, off_t, enum rump_uiorw);
size_t rump_pub_uio_getresid(struct uio *);
off_t rump_pub_uio_getoff(struct uio *);
size_t rump_pub_uio_free(struct uio *);
struct kauth_cred* rump_pub_cred_create(uid_t, gid_t, size_t, gid_t *);
void rump_pub_cred_put(struct kauth_cred *);
int rump_pub_lwproc_rfork(int);
int rump_pub_lwproc_newlwp(pid_t);
void rump_pub_lwproc_switch(struct lwp *);
void rump_pub_lwproc_releaselwp(void);
struct lwp * rump_pub_lwproc_curlwp(void);
void rump_pub_lwproc_sysent_usenative(void);
void rump_pub_allbetsareoff_setid(pid_t, int);

int rump_pub_etfs_register(const char *, const char *, int rump_etfs_type);

extern int rump_i_know_what_i_am_doing_with_sysents;
void rump_pub_lwproc_sysent_usenative(void);
]]

