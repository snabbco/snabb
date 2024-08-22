/*
** Error handling.
** Copyright (C) 2005-2023 Mike Pall. See Copyright Notice in luajit.h
*/

#define lj_err_c
#define LUA_CORE

#include "lj_obj.h"
#include "lj_err.h"
#include "lj_debug.h"
#include "lj_str.h"
#include "lj_func.h"
#include "lj_state.h"
#include "lj_frame.h"
#include "lj_ff.h"
#include "lj_trace.h"
#include "lj_vm.h"
#include "lj_strfmt.h"

/* -- Error messages ------------------------------------------------------ */

/* Error message strings. */
LJ_DATADEF const char *lj_err_allmsg =
#define ERRDEF(name, msg)	msg "\0"
#include "lj_errmsg.h"
;

/* -- Internal frame unwinding -------------------------------------------- */

/* Unwind Lua stack and move error message to new top. */
LJ_NOINLINE static void unwindstack(lua_State *L, TValue *top)
{
  lj_func_closeuv(L, top);
  if (top < L->top-1) {
    copyTV(L, top, L->top-1);
    L->top = top+1;
  }
  lj_state_relimitstack(L);
}

/* Unwind until stop frame. Optionally cleanup frames. */
static void *err_unwind(lua_State *L, void *stopcf, int errcode)
{
  TValue *frame = L->base-1;
  void *cf = L->cframe;
  while (cf) {
    int32_t nres = cframe_nres(cframe_raw(cf));
    if (nres < 0) {  /* C frame without Lua frame? */
      TValue *top = restorestack(L, -nres);
      if (frame < top) {  /* Frame reached? */
	if (errcode) {
	  L->base = frame+1;
	  L->cframe = cframe_prev(cf);
	  unwindstack(L, top);
	}
	return cf;
      }
    }
    if (frame <= tvref(L->stack)+LJ_FR2)
      break;
    switch (frame_typep(frame)) {
    case FRAME_LUA:  /* Lua frame. */
    case FRAME_LUAP:
      frame = frame_prevl(frame);
      break;
    case FRAME_C:  /* C frame. */
    unwind_c:
      UNUSED(stopcf);
      cf = cframe_prev(cf);
      frame = frame_prevd(frame);
      break;
    case FRAME_CP:  /* Protected C frame. */
      if (cframe_canyield(cf)) {  /* Resume? */
	if (errcode) {
	  hook_leave(G(L));  /* Assumes nobody uses coroutines inside hooks. */
	  L->cframe = NULL;
	  L->status = (uint8_t)errcode;
	}
	return cf;
      }
      if (errcode) {
	L->base = frame_prevd(frame) + 1;
	L->cframe = cframe_prev(cf);
	unwindstack(L, frame - LJ_FR2);
      }
      return cf;
    case FRAME_CONT:  /* Continuation frame. */
      if (frame_iscont_fficb(frame))
	goto unwind_c;
      /* fallthrough */
    case FRAME_VARG:  /* Vararg frame. */
      frame = frame_prevd(frame);
      break;
    case FRAME_PCALL:  /* FF pcall() frame. */
    case FRAME_PCALLH:  /* FF pcall() frame inside hook. */
      if (errcode) {
	global_State *g;
	if (errcode == LUA_YIELD) {
	  frame = frame_prevd(frame);
	  break;
	}
	g = G(L);
	setgcref(g->cur_L, obj2gco(L));
	if (frame_typep(frame) == FRAME_PCALL)
	  hook_leave(g);
	L->base = frame_prevd(frame) + 1;
	L->cframe = cf;
	unwindstack(L, L->base);
      }
      return (void *)((intptr_t)cf | CFRAME_UNWIND_FF);
    }
  }
  /* No C frame. */
  if (errcode) {
    L->base = tvref(L->stack)+1+LJ_FR2;
    L->cframe = NULL;
    unwindstack(L, L->base);
    if (G(L)->panic)
      G(L)->panic(L);
    exit(EXIT_FAILURE);
  }
  return L;  /* Anything non-NULL will do. */
}

/* -- Error handling ------------------------------------------------------ */

/* Throw error. Find catch frame, unwind stack and continue. */
LJ_NOINLINE void lj_err_throw(lua_State *L, int errcode)
{
  global_State *g = G(L);
  lj_trace_abort(g);
  L->status = LUA_OK;
  {
    void *cf = err_unwind(L, NULL, errcode);
    if (cframe_unwind_ff(cf))
      lj_vm_unwind_ff(cframe_raw(cf));
    else
      lj_vm_unwind_c(cframe_raw(cf), errcode);
  }
  exit(EXIT_FAILURE);
}

/* Return string object for error message. */
LJ_NOINLINE GCstr *lj_err_str(lua_State *L, ErrMsg em)
{
  return lj_str_newz(L, err2msg(em));
}

/* Out-of-memory error. */
LJ_NOINLINE void lj_err_mem(lua_State *L)
{
  if (L->status == LUA_ERRERR+1)  /* Don't touch the stack during lua_open. */
    lj_vm_unwind_c(L->cframe, LUA_ERRMEM);
  if (LJ_HASJIT) {
    TValue *base = tvref(G(L)->jit_base);
    if (base) L->base = base;
  }
  if (curr_funcisL(L)) {
    L->top = curr_topL(L);
    if (LJ_UNLIKELY(L->top > tvref(L->maxstack))) {
      /* The current Lua frame violates the stack. Replace it with a dummy. */
      L->top = L->base;
      setframe_gc(L->base - 1 - LJ_FR2, obj2gco(L), LJ_TTHREAD);
    }
  }
  setstrV(L, L->top++, lj_err_str(L, LJ_ERR_ERRMEM));
  lj_err_throw(L, LUA_ERRMEM);
}

/* Find error function for runtime errors. Requires an extra stack traversal. */
static ptrdiff_t finderrfunc(lua_State *L)
{
  cTValue *frame = L->base-1, *bot = tvref(L->stack)+LJ_FR2;
  void *cf = L->cframe;
  while (frame > bot && cf) {
    while (cframe_nres(cframe_raw(cf)) < 0) {  /* cframe without frame? */
      if (frame >= restorestack(L, -cframe_nres(cf)))
	break;
      if (cframe_errfunc(cf) >= 0)  /* Error handler not inherited (-1)? */
	return cframe_errfunc(cf);
      cf = cframe_prev(cf);  /* Else unwind cframe and continue searching. */
      if (cf == NULL)
	return 0;
    }
    switch (frame_typep(frame)) {
    case FRAME_LUA:
    case FRAME_LUAP:
      frame = frame_prevl(frame);
      break;
    case FRAME_C:
      cf = cframe_prev(cf);
      /* fallthrough */
    case FRAME_VARG:
      frame = frame_prevd(frame);
      break;
    case FRAME_CONT:
      if (frame_iscont_fficb(frame))
	cf = cframe_prev(cf);
      frame = frame_prevd(frame);
      break;
    case FRAME_CP:
      if (cframe_canyield(cf)) return 0;
      if (cframe_errfunc(cf) >= 0)
	return cframe_errfunc(cf);
      cf = cframe_prev(cf);
      frame = frame_prevd(frame);
      break;
    case FRAME_PCALL:
    case FRAME_PCALLH:
      if (frame_func(frame_prevd(frame))->c.ffid == FF_xpcall)
	return savestack(L, frame_prevd(frame)+1);  /* xpcall's errorfunc. */
      return 0;
    default:
      lj_assertL(0, "bad frame type");
      return 0;
    }
  }
  return 0;
}

/* Runtime error. */
LJ_NOINLINE void lj_err_run(lua_State *L)
{
  ptrdiff_t ef = tvref(G(L)->jit_base) ? 0 : finderrfunc(L);
  if (ef) {
    TValue *errfunc, *top;
    lj_state_checkstack(L, LUA_MINSTACK * 2);  /* Might raise new error. */
    lj_trace_abort(G(L));
    errfunc = restorestack(L, ef);
    top = L->top;
    if (!tvisfunc(errfunc) || L->status == LUA_ERRERR) {
      setstrV(L, top-1, lj_err_str(L, LJ_ERR_ERRERR));
      lj_err_throw(L, LUA_ERRERR);
    }
    L->status = LUA_ERRERR;
    copyTV(L, top+LJ_FR2, top-1);
    copyTV(L, top-1, errfunc);
    if (LJ_FR2) setnilV(top++);
    L->top = top+1;
    lj_vm_call(L, top, 1+1);  /* Stack: |errfunc|msg| -> |msg| */
  }
  lj_err_throw(L, LUA_ERRRUN);
}

/* Stack overflow error. */
void lj_err_stkov(lua_State *L)
{
  lj_debug_addloc(L, err2msg(LJ_ERR_STKOV), L->base-1, NULL);
  lj_err_run(L);
}

/* Rethrow error after doing a trace exit. */
LJ_NOINLINE void lj_err_trace(lua_State *L, int errcode)
{
  if (errcode == LUA_ERRRUN)
    lj_err_run(L);
  else
    lj_err_throw(L, errcode);
}

/* Formatted runtime error message. */
LJ_NORET LJ_NOINLINE static void err_msgv(lua_State *L, ErrMsg em, ...)
{
  const char *msg;
  va_list argp;
  va_start(argp, em);
  if (LJ_HASJIT) {
    TValue *base = tvref(G(L)->jit_base);
    if (base) L->base = base;
  }
  if (curr_funcisL(L)) L->top = curr_topL(L);
  msg = lj_strfmt_pushvf(L, err2msg(em), argp);
  va_end(argp);
  lj_debug_addloc(L, msg, L->base-1, NULL);
  lj_err_run(L);
}

/* Non-vararg variant for better calling conventions. */
LJ_NOINLINE void lj_err_msg(lua_State *L, ErrMsg em)
{
  err_msgv(L, em);
}

/* Lexer error. */
LJ_NOINLINE void lj_err_lex(lua_State *L, GCstr *src, const char *tok,
			    BCLine line, ErrMsg em, va_list argp)
{
  char buff[LUA_IDSIZE];
  const char *msg;
  lj_debug_shortname(buff, src, line);
  msg = lj_strfmt_pushvf(L, err2msg(em), argp);
  msg = lj_strfmt_pushf(L, "%s:%d: %s", buff, line, msg);
  if (tok)
    lj_strfmt_pushf(L, err2msg(LJ_ERR_XNEAR), msg, tok);
  lj_err_throw(L, LUA_ERRSYNTAX);
}

/* Typecheck error for operands. */
LJ_NOINLINE void lj_err_optype(lua_State *L, cTValue *o, ErrMsg opm)
{
  const char *tname = lj_typename(o);
  const char *opname = err2msg(opm);
  if (curr_funcisL(L)) {
    GCproto *pt = curr_proto(L);
    const BCIns *pc = cframe_Lpc(L) - 1;
    const char *oname = NULL;
    const char *kind = lj_debug_slotname(pt, pc, (BCReg)(o-L->base), &oname);
    if (kind)
      err_msgv(L, LJ_ERR_BADOPRT, opname, kind, oname, tname);
  }
  err_msgv(L, LJ_ERR_BADOPRV, opname, tname);
}

/* Typecheck error for ordered comparisons. */
LJ_NOINLINE void lj_err_comp(lua_State *L, cTValue *o1, cTValue *o2)
{
  const char *t1 = lj_typename(o1);
  const char *t2 = lj_typename(o2);
  err_msgv(L, t1 == t2 ? LJ_ERR_BADCMPV : LJ_ERR_BADCMPT, t1, t2);
  /* This assumes the two "boolean" entries are commoned by the C compiler. */
}

/* Typecheck error for __call. */
LJ_NOINLINE void lj_err_optype_call(lua_State *L, TValue *o)
{
  /* Gross hack if lua_[p]call or pcall/xpcall fail for a non-callable object:
  ** L->base still points to the caller. So add a dummy frame with L instead
  ** of a function. See lua_getstack().
  */
  const BCIns *pc = cframe_Lpc(L);
  if (((ptrdiff_t)pc & FRAME_TYPE) != FRAME_LUA) {
    const char *tname = lj_typename(o);
    setframe_gc(o, obj2gco(L), LJ_TTHREAD);
    if (LJ_FR2) o++;
    setframe_pc(o, pc);
    L->top = L->base = o+1;
    err_msgv(L, LJ_ERR_BADCALL, tname);
  }
  lj_err_optype(L, o, LJ_ERR_OPCALL);
}

/* Error in context of caller. */
LJ_NOINLINE void lj_err_callermsg(lua_State *L, const char *msg)
{
  TValue *frame = NULL, *pframe = NULL;
  if (!(LJ_HASJIT && tvref(G(L)->jit_base))) {
    frame = L->base-1;
    if (frame_islua(frame)) {
      pframe = frame_prevl(frame);
    } else if (frame_iscont(frame)) {
      if (frame_iscont_fficb(frame)) {
	pframe = frame;
	frame = NULL;
      } else {
	pframe = frame_prevd(frame);
	/* Remove frame for FFI metamethods. */
	if (frame_func(frame)->c.ffid >= FF_ffi_meta___index &&
	    frame_func(frame)->c.ffid <= FF_ffi_meta___tostring) {
	  L->base = pframe+1;
	  L->top = frame;
	  setcframe_pc(cframe_raw(L->cframe), frame_contpc(frame));
	}
      }
    }
  }
  lj_debug_addloc(L, msg, pframe, frame);
  lj_err_run(L);
}

/* Formatted error in context of caller. */
LJ_NOINLINE void lj_err_callerv(lua_State *L, ErrMsg em, ...)
{
  const char *msg;
  va_list argp;
  va_start(argp, em);
  msg = lj_strfmt_pushvf(L, err2msg(em), argp);
  va_end(argp);
  lj_err_callermsg(L, msg);
}

/* Error in context of caller. */
LJ_NOINLINE void lj_err_caller(lua_State *L, ErrMsg em)
{
  lj_err_callermsg(L, err2msg(em));
}

/* Argument error message. */
LJ_NORET LJ_NOINLINE static void err_argmsg(lua_State *L, int narg,
					    const char *msg)
{
  const char *fname = "?";
  const char *ftype = lj_debug_funcname(L, L->base - 1, &fname);
  if (narg < 0 && narg > LUA_REGISTRYINDEX)
    narg = (int)(L->top - L->base) + narg + 1;
  if (ftype && ftype[3] == 'h' && --narg == 0)  /* Check for "method". */
    msg = lj_strfmt_pushf(L, err2msg(LJ_ERR_BADSELF), fname, msg);
  else
    msg = lj_strfmt_pushf(L, err2msg(LJ_ERR_BADARG), narg, fname, msg);
  lj_err_callermsg(L, msg);
}

/* Formatted argument error. */
LJ_NOINLINE void lj_err_argv(lua_State *L, int narg, ErrMsg em, ...)
{
  const char *msg;
  va_list argp;
  va_start(argp, em);
  msg = lj_strfmt_pushvf(L, err2msg(em), argp);
  va_end(argp);
  err_argmsg(L, narg, msg);
}

/* Argument error. */
LJ_NOINLINE void lj_err_arg(lua_State *L, int narg, ErrMsg em)
{
  err_argmsg(L, narg, err2msg(em));
}

/* Typecheck error for arguments. */
LJ_NOINLINE void lj_err_argtype(lua_State *L, int narg, const char *xname)
{
  const char *tname, *msg;
  if (narg <= LUA_REGISTRYINDEX) {
    if (narg >= LUA_GLOBALSINDEX) {
      tname = lj_obj_itypename[~LJ_TTAB];
    } else {
      GCfunc *fn = curr_func(L);
      int idx = LUA_GLOBALSINDEX - narg;
      if (idx <= fn->c.nupvalues)
	tname = lj_typename(&fn->c.upvalue[idx-1]);
      else
	tname = lj_obj_typename[0];
    }
  } else {
    TValue *o = narg < 0 ? L->top + narg : L->base + narg-1;
    tname = o < L->top ? lj_typename(o) : lj_obj_typename[0];
  }
  msg = lj_strfmt_pushf(L, err2msg(LJ_ERR_BADTYPE), xname, tname);
  err_argmsg(L, narg, msg);
}

/* Typecheck error for arguments. */
LJ_NOINLINE void lj_err_argt(lua_State *L, int narg, int tt)
{
  lj_err_argtype(L, narg, lj_obj_typename[tt+1]);
}

/* -- Public error handling API ------------------------------------------- */

LUA_API lua_CFunction lua_atpanic(lua_State *L, lua_CFunction panicf)
{
  lua_CFunction old = G(L)->panic;
  G(L)->panic = panicf;
  return old;
}

/* Forwarders for the public API (C calling convention and no LJ_NORET). */
LUA_API int lua_error(lua_State *L)
{
  lj_err_run(L);
  return 0;  /* unreachable */
}

LUALIB_API int luaL_argerror(lua_State *L, int narg, const char *msg)
{
  err_argmsg(L, narg, msg);
  return 0;  /* unreachable */
}

LUALIB_API int luaL_typerror(lua_State *L, int narg, const char *xname)
{
  lj_err_argtype(L, narg, xname);
  return 0;  /* unreachable */
}

LUALIB_API void luaL_where(lua_State *L, int level)
{
  int size;
  cTValue *frame = lj_debug_frame(L, level, &size);
  lj_debug_addloc(L, "", frame, size ? frame+size : NULL);
}

LUALIB_API int luaL_error(lua_State *L, const char *fmt, ...)
{
  const char *msg;
  va_list argp;
  va_start(argp, fmt);
  msg = lj_strfmt_pushvf(L, fmt, argp);
  va_end(argp);
  lj_err_callermsg(L, msg);
  return 0;  /* unreachable */
}

