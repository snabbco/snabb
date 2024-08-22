/*
** FFI C library loader.
** Copyright (C) 2005-2023 Mike Pall. See Copyright Notice in luajit.h
*/

#include "lj_obj.h"


#include "lj_gc.h"
#include "lj_err.h"
#include "lj_tab.h"
#include "lj_str.h"
#include "lj_udata.h"
#include "lj_ctype.h"
#include "lj_cconv.h"
#include "lj_cdata.h"
#include "lj_clib.h"
#include "lj_strfmt.h"

/* -- OS-specific functions ----------------------------------------------- */


#include <dlfcn.h>
#include <stdio.h>

#if defined(RTLD_DEFAULT) && !defined(NO_RTLD_DEFAULT)
#define CLIB_DEFHANDLE	RTLD_DEFAULT
#elif LJ_TARGET_OSX || LJ_TARGET_BSD
#define CLIB_DEFHANDLE	((void *)(intptr_t)-2)
#else
#define CLIB_DEFHANDLE	NULL
#endif

LJ_NORET LJ_NOINLINE static void clib_error_(lua_State *L)
{
  lj_err_callermsg(L, dlerror());
}

#define clib_error(L, fmt, name)	clib_error_(L)

#define CLIB_SOPREFIX	"lib"

#if LJ_TARGET_OSX
#define CLIB_SOEXT	"%s.dylib"
#else
#define CLIB_SOEXT	"%s.so"
#endif

static const char *clib_extname(lua_State *L, const char *name)
{
  if (!strchr(name, '/')
     ) {
    if (!strchr(name, '.')) {
      name = lj_strfmt_pushf(L, CLIB_SOEXT, name);
      L->top--;
    }
    if (!(name[0] == CLIB_SOPREFIX[0] && name[1] == CLIB_SOPREFIX[1] &&
	  name[2] == CLIB_SOPREFIX[2])) {
      name = lj_strfmt_pushf(L, CLIB_SOPREFIX "%s", name);
      L->top--;
    }
  }
  return name;
}

/* Check for a recognized ld script line. */
static const char *clib_check_lds(lua_State *L, const char *buf)
{
  char *p, *e;
  if ((!strncmp(buf, "GROUP", 5) || !strncmp(buf, "INPUT", 5)) &&
      (p = strchr(buf, '('))) {
    while (*++p == ' ') ;
    for (e = p; *e && *e != ' ' && *e != ')'; e++) ;
    return strdata(lj_str_new(L, p, e-p));
  }
  return NULL;
}

/* Quick and dirty solution to resolve shared library name from ld script. */
static const char *clib_resolve_lds(lua_State *L, const char *name)
{
  FILE *fp = fopen(name, "r");
  const char *p = NULL;
  if (fp) {
    char buf[256];
    if (fgets(buf, sizeof(buf), fp)) {
      if (!strncmp(buf, "/* GNU ld script", 16)) {  /* ld script magic? */
	while (fgets(buf, sizeof(buf), fp)) {  /* Check all lines. */
	  p = clib_check_lds(L, buf);
	  if (p) break;
	}
      } else {  /* Otherwise check only the first line. */
	p = clib_check_lds(L, buf);
      }
    }
    fclose(fp);
  }
  return p;
}

static void *clib_loadlib(lua_State *L, const char *name, int global)
{
  void *h = dlopen(clib_extname(L, name),
		   RTLD_LAZY | (global?RTLD_GLOBAL:RTLD_LOCAL));
  if (!h) {
    const char *e, *err = dlerror();
    if (err && *err == '/' && (e = strchr(err, ':')) &&
	(name = clib_resolve_lds(L, strdata(lj_str_new(L, err, e-err))))) {
      h = dlopen(name, RTLD_LAZY | (global?RTLD_GLOBAL:RTLD_LOCAL));
      if (h) return h;
      err = dlerror();
    }
    if (!err) err = "dlopen failed";
    lj_err_callermsg(L, err);
  }
  return h;
}

static void clib_unloadlib(CLibrary *cl)
{
  if (cl->handle && cl->handle != CLIB_DEFHANDLE)
    dlclose(cl->handle);
}

static void *clib_getsym(CLibrary *cl, const char *name)
{
  void *p = dlsym(cl->handle, name);
  return p;
}


/* -- C library indexing -------------------------------------------------- */


/* Get redirected or mangled external symbol. */
static const char *clib_extsym(CTState *cts, CType *ct, GCstr *name)
{
  if (ct->sib) {
    CType *ctf = ctype_get(cts, ct->sib);
    if (ctype_isxattrib(ctf->info, CTA_REDIR))
      return strdata(gco2str(gcref(ctf->name)));
  }
  return strdata(name);
}

/* Index a C library by name. */
TValue *lj_clib_index(lua_State *L, CLibrary *cl, GCstr *name)
{
  TValue *tv = lj_tab_setstr(L, cl->cache, name);
  if (LJ_UNLIKELY(tvisnil(tv))) {
    CTState *cts = ctype_cts(L);
    CType *ct;
    CTypeID id = lj_ctype_getname(cts, &ct, name, CLNS_INDEX);
    if (!id)
      lj_err_callerv(L, LJ_ERR_FFI_NODECL, strdata(name));
    if (ctype_isconstval(ct->info)) {
      CType *ctt = ctype_child(cts, ct);
      lj_assertCTS(ctype_isinteger(ctt->info) && ctt->size <= 4,
		   "only 32 bit const supported");  /* NYI */
      if ((ctt->info & CTF_UNSIGNED) && (int32_t)ct->size < 0)
	setnumV(tv, (lua_Number)(uint32_t)ct->size);
      else
	setintV(tv, (int32_t)ct->size);
    } else {
      const char *sym = clib_extsym(cts, ct, name);
      void *p = clib_getsym(cl, sym);
      GCcdata *cd;
      lj_assertCTS(ctype_isfunc(ct->info) || ctype_isextern(ct->info),
		   "unexpected ctype %08x in clib", ct->info);
      if (!p)
	clib_error(L, "cannot resolve symbol " LUA_QS ": %s", sym);
      cd = lj_cdata_new(cts, id, CTSIZE_PTR);
      *(void **)cdataptr(cd) = p;
      setcdataV(L, tv, cd);
      lj_gc_anybarriert(L, cl->cache);
    }
  }
  return tv;
}

/* -- C library management ------------------------------------------------ */

/* Create a new CLibrary object and push it on the stack. */
static CLibrary *clib_new(lua_State *L, GCtab *mt)
{
  GCtab *t = lj_tab_new(L, 0, 0);
  GCudata *ud = lj_udata_new(L, sizeof(CLibrary), t);
  CLibrary *cl = (CLibrary *)uddata(ud);
  cl->cache = t;
  ud->udtype = UDTYPE_FFI_CLIB;
  /* NOBARRIER: The GCudata is new (marked white). */
  setgcref(ud->metatable, obj2gco(mt));
  setudataV(L, L->top++, ud);
  return cl;
}

/* Load a C library. */
void lj_clib_load(lua_State *L, GCtab *mt, GCstr *name, int global)
{
  void *handle = clib_loadlib(L, strdata(name), global);
  CLibrary *cl = clib_new(L, mt);
  cl->handle = handle;
}

/* Unload a C library. */
void lj_clib_unload(CLibrary *cl)
{
  clib_unloadlib(cl);
  cl->handle = NULL;
}

/* Create the default C library object. */
void lj_clib_default(lua_State *L, GCtab *mt)
{
  CLibrary *cl = clib_new(L, mt);
  cl->handle = CLIB_DEFHANDLE;
}

