/*
** JIT library.
** Copyright (C) 2005-2017 Mike Pall. See Copyright Notice in luajit.h
*/

#define lib_jit_c
#define LUA_LIB

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include "lj_obj.h"
#include "lj_gc.h"
#include "lj_err.h"
#include "lj_debug.h"
#include "lj_str.h"
#include "lj_tab.h"
#include "lj_state.h"
#include "lj_bc.h"
#include "lj_ctype.h"
#include "lj_ir.h"
#include "lj_jit.h"
#include "lj_ircall.h"
#include "lj_iropt.h"
#include "lj_target.h"
#include "lj_trace.h"
#include "lj_dispatch.h"
#include "lj_vm.h"
#include "lj_lib.h"
#include "lj_auditlog.h"

#include "luajit.h"

/* -- jit.* functions ----------------------------------------------------- */

#define LJLIB_MODULE_jit

static int setjitmode(lua_State *L, int mode)
{
  int idx = 0;
  if (L->base == L->top || tvisnil(L->base)) {  /* jit.on/off/flush([nil]) */
    mode |= LUAJIT_MODE_ENGINE;
  } else {
    /* jit.on/off/flush(func|proto, nil|true|false) */
    if (tvisfunc(L->base) || tvisproto(L->base))
      idx = 1;
    else if (!tvistrue(L->base))  /* jit.on/off/flush(true, nil|true|false) */
      goto err;
    if (L->base+1 < L->top && tvisbool(L->base+1))
      mode |= boolV(L->base+1) ? LUAJIT_MODE_ALLFUNC : LUAJIT_MODE_ALLSUBFUNC;
    else
      mode |= LUAJIT_MODE_FUNC;
  }
  if (luaJIT_setmode(L, idx, mode) != 1) {
    if ((mode & LUAJIT_MODE_MASK) == LUAJIT_MODE_ENGINE)
      lj_err_caller(L, LJ_ERR_NOJIT);
  err:
    lj_err_argt(L, 1, LUA_TFUNCTION);
  }
  return 0;
}

LJLIB_CF(jit_on)
{
  return setjitmode(L, LUAJIT_MODE_ON);
}

LJLIB_CF(jit_off)
{
  return setjitmode(L, LUAJIT_MODE_OFF);
}

LJLIB_CF(jit_flush)
{
  if (L->base < L->top && tvisnumber(L->base)) {
    int traceno = lj_lib_checkint(L, 1);
    luaJIT_setmode(L, traceno, LUAJIT_MODE_FLUSH|LUAJIT_MODE_TRACE);
    return 0;
  }
  return setjitmode(L, LUAJIT_MODE_FLUSH);
}

LJLIB_CF(jit_auditlog)
{
  if (L->base < L->top && tvisstr(L->base)) {
    /* XXX Support auditlog file size argument. */
    if (lj_auditlog_open(strdata(lj_lib_checkstr(L, 1)), 0)) {
      return 0;
    } else {
      lj_err_caller(L, LJ_ERR_AUDITLOG);
    }
  } else {
    lj_err_argtype(L, 1, "string filename");
  }
}

/* Push a string for every flag bit that is set. */
static void flagbits_to_strings(lua_State *L, uint32_t flags, uint32_t base,
				const char *str)
{
  for (; *str; base <<= 1, str += 1+*str)
    if (flags & base)
      setstrV(L, L->top++, lj_str_new(L, str+1, *(uint8_t *)str));
}

LJLIB_CF(jit_status)
{
  jit_State *J = L2J(L);
  L->top = L->base;
  setboolV(L->top++, (J->flags & JIT_F_ON) ? 1 : 0);
  flagbits_to_strings(L, J->flags, JIT_F_CPU_FIRST, JIT_F_CPUSTRING);
  flagbits_to_strings(L, J->flags, JIT_F_OPT_FIRST, JIT_F_OPTSTRING);
  return (int)(L->top - L->base);
}

/* Calling this forces a trace stitch. */
LJLIB_CF(jit_tracebarrier)
{
  return 0;
}

LJLIB_PUSH(top-5) LJLIB_SET(os)
LJLIB_PUSH(top-4) LJLIB_SET(arch)
LJLIB_PUSH(top-3) LJLIB_SET(version_num)
LJLIB_PUSH(top-2) LJLIB_SET(version)

#include "lj_libdef.h"

/* -- jit.opt module ------------------------------------------------------ */


#define LJLIB_MODULE_jit_opt

/* Parse optimization level. */
static int jitopt_level(jit_State *J, const char *str)
{
  if (str[0] >= '0' && str[0] <= '9' && str[1] == '\0') {
    uint32_t flags;
    if (str[0] == '0') flags = JIT_F_OPT_0;
    else if (str[0] == '1') flags = JIT_F_OPT_1;
    else if (str[0] == '2') flags = JIT_F_OPT_2;
    else flags = JIT_F_OPT_3;
    J->flags = (J->flags & ~JIT_F_OPT_MASK) | flags;
    return 1;  /* Ok. */
  }
  return 0;  /* No match. */
}

/* Parse optimization flag. */
static int jitopt_flag(jit_State *J, const char *str)
{
  const char *lst = JIT_F_OPTSTRING;
  uint32_t opt;
  int set = 1;
  if (str[0] == '+') {
    str++;
  } else if (str[0] == '-') {
    str++;
    set = 0;
  } else if (str[0] == 'n' && str[1] == 'o') {
    str += str[2] == '-' ? 3 : 2;
    set = 0;
  }
  for (opt = JIT_F_OPT_FIRST; ; opt <<= 1) {
    size_t len = *(const uint8_t *)lst;
    if (len == 0)
      break;
    if (strncmp(str, lst+1, len) == 0 && str[len] == '\0') {
      if (set) J->flags |= opt; else J->flags &= ~opt;
      return 1;  /* Ok. */
    }
    lst += 1+len;
  }
  return 0;  /* No match. */
}

/* Parse optimization parameter. */
static int jitopt_param(jit_State *J, const char *str)
{
  const char *lst = JIT_P_STRING;
  int i;
  for (i = 0; i < JIT_P__MAX; i++) {
    size_t len = *(const uint8_t *)lst;
    lua_assert(len != 0);
    if (strncmp(str, lst+1, len) == 0 && str[len] == '=') {
      int32_t n = 0;
      const char *p = &str[len+1];
      while (*p >= '0' && *p <= '9')
	n = n*10 + (*p++ - '0');
      if (*p) return 0;  /* Malformed number. */
      J->param[i] = n;
      if (i == JIT_P_hotloop)
	lj_dispatch_init_hotcount(J2G(J));
      return 1;  /* Ok. */
    }
    lst += 1+len;
  }
  return 0;  /* No match. */
}

/* jit.opt.start(flags...) */
LJLIB_CF(jit_opt_start)
{
  jit_State *J = L2J(L);
  int nargs = (int)(L->top - L->base);
  if (nargs == 0) {
    J->flags = (J->flags & ~JIT_F_OPT_MASK) | JIT_F_OPT_DEFAULT;
  } else {
    int i;
    for (i = 1; i <= nargs; i++) {
      const char *str = strdata(lj_lib_checkstr(L, i));
      if (!jitopt_level(J, str) &&
	  !jitopt_flag(J, str) &&
	  !jitopt_param(J, str))
	lj_err_callerv(L, LJ_ERR_JITOPT, str);
    }
  }
  return 0;
}

#include "lj_libdef.h"

/* -- jit.vmprofile module  ----------------------------------------------- */

#define LJLIB_MODULE_jit_vmprofile

LJLIB_CF(jit_vmprofile_open)
{
  int nargs = (int)(L->top - L->base);
  int nostart = nargs >= 3 ? boolV(L->base+2) : 0;
  int noselect = nargs >= 2 ? boolV(L->base+1) : 0;
  const char *filename = nargs >= 1 ? strdata(lj_lib_checkstr(L, 1)) : NULL;
  if (filename) {
    return luaJIT_vmprofile_open(L, filename, noselect, nostart);
  } else {
    lj_err_argtype(L, 1, "filename");
  }
}

LJLIB_CF(jit_vmprofile_close)
{
  if (L->base < L->top && tvislightud(L->base)) {
    return luaJIT_vmprofile_close(L, lightudV(L->base));
  } else {
    lj_err_argtype(L, 1, "vmprofile");
  }
}

LJLIB_CF(jit_vmprofile_select)
{
  if (L->base < L->top && tvislightud(L->base)) {
    return luaJIT_vmprofile_select(L, lightudV(L->base));
  } else {
    lj_err_argtype(L, 1, "vmprofile");
  }
}

LJLIB_CF(jit_vmprofile_start)
{
  return luaJIT_vmprofile_start(L);
}

LJLIB_CF(jit_vmprofile_stop)
{
  return luaJIT_vmprofile_stop(L);
}

#include "lj_libdef.h"

/* -- JIT compiler initialization ----------------------------------------- */

/* Default values for JIT parameters. */
static const int32_t jit_param_default[JIT_P__MAX+1] = {
#define JIT_PARAMINIT(len, name, value)	(value),
JIT_PARAMDEF(JIT_PARAMINIT)
#undef JIT_PARAMINIT
  0
};

/* Arch-dependent CPU detection. */
static uint32_t jit_cpudetect(lua_State *L)
{
  uint32_t flags = 0;
  uint32_t vendor[4];
  uint32_t features[4];
  if (lj_vm_cpuid(0, vendor) && lj_vm_cpuid(1, features)) {
    flags |= ((features[3] >> 26)&1) * JIT_F_SSE2;
    flags |= ((features[2] >> 0)&1) * JIT_F_SSE3;
    flags |= ((features[2] >> 19)&1) * JIT_F_SSE4_1;
    if (vendor[2] == 0x6c65746e) {  /* Intel. */
      if ((features[0] & 0x0fff0ff0) == 0x000106c0)  /* Atom. */
	flags |= JIT_F_LEA_AGU;
    } else if (vendor[2] == 0x444d4163) {  /* AMD. */
      uint32_t fam = (features[0] & 0x0ff00f00);
      if (fam >= 0x00000f00)  /* K8, K10. */
	flags |= JIT_F_PREFER_IMUL;
    }
    if (vendor[0] >= 7) {
      uint32_t xfeatures[4];
      lj_vm_cpuid(7, xfeatures);
      flags |= ((xfeatures[1] >> 8)&1) * JIT_F_BMI2;
    }
  }
  /* Check for required instruction set support on x86 (unnecessary on x64). */
  UNUSED(L);
  return flags;
}

/* Initialize JIT compiler. */
static void jit_init(lua_State *L)
{
  uint32_t flags = jit_cpudetect(L);
  jit_State *J = L2J(L);
  J->flags = flags | JIT_F_ON | JIT_F_OPT_DEFAULT;
  memcpy(J->param, jit_param_default, sizeof(J->param));
  lj_dispatch_update(G(L));
}

LUALIB_API int luaopen_jit(lua_State *L)
{
  jit_init(L);
  lua_pushliteral(L, LJ_OS_NAME);
  lua_pushliteral(L, LJ_ARCH_NAME);
  lua_pushinteger(L, LUAJIT_VERSION_NUM);
  lua_pushliteral(L, LUAJIT_VERSION);
  LJ_LIB_REG(L, LUA_JITLIBNAME, jit);
  LJ_LIB_REG(L, "jit.vmprofile", jit_vmprofile);
  LJ_LIB_REG(L, "jit.opt", jit_opt);
  L->top -= 2;
  return 1;
}

