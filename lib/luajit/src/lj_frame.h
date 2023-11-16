/*
** Stack frames.
** Copyright (C) 2005-2022 Mike Pall. See Copyright Notice in luajit.h
*/

#ifndef _LJ_FRAME_H
#define _LJ_FRAME_H

#include "lj_obj.h"
#include "lj_bc.h"

/* -- Lua stack frame ----------------------------------------------------- */

/* Frame type markers in LSB of PC (4-byte aligned) or delta (8-byte aligned:
**
**    PC  00  Lua frame
** delta 001  C frame
** delta 010  Continuation frame
** delta 011  Lua vararg frame
** delta 101  cpcall() frame
** delta 110  ff pcall() frame
** delta 111  ff pcall() frame with active hook
*/
enum {
  FRAME_LUA, FRAME_C, FRAME_CONT, FRAME_VARG,
  FRAME_LUAP, FRAME_CP, FRAME_PCALL, FRAME_PCALLH
};
#define FRAME_TYPE		3
#define FRAME_P			4
#define FRAME_TYPEP		(FRAME_TYPE|FRAME_P)

/* Macros to access and modify Lua frames. */
/* Two-slot frame info, required for 64 bit PC/GCRef:
**
**                   base-2  base-1      |  base  base+1 ...
**                  [func   PC/delta/ft] | [slots ...]
**                  ^-- frame            | ^-- base   ^-- top
**
** Continuation frames:
**
**   base-4  base-3  base-2  base-1      |  base  base+1 ...
**  [cont      PC ] [func   PC/delta/ft] | [slots ...]
**                  ^-- frame            | ^-- base   ^-- top
*/
#define frame_gc(f)		(gcval((f)-1))
#define frame_ftsz(f)		((ptrdiff_t)(f)->ftsz)
#define frame_pc(f)		((const BCIns *)frame_ftsz(f))
#define setframe_gc(f, p, tp)	(setgcVraw((f), (p), (tp)))
#define setframe_ftsz(f, sz)	((f)->ftsz = (sz))
#define setframe_pc(f, pc)	((f)->ftsz = (int64_t)(intptr_t)(pc))

#define frame_type(f)		(frame_ftsz(f) & FRAME_TYPE)
#define frame_typep(f)		(frame_ftsz(f) & FRAME_TYPEP)
#define frame_islua(f)		(frame_type(f) == FRAME_LUA)
#define frame_isc(f)		(frame_type(f) == FRAME_C)
#define frame_iscont(f)		(frame_typep(f) == FRAME_CONT)
#define frame_isvarg(f)		(frame_typep(f) == FRAME_VARG)
#define frame_ispcall(f)	((frame_ftsz(f) & 6) == FRAME_PCALL)

#define frame_func(f)		(&frame_gc(f)->fn)
#define frame_delta(f)		(frame_ftsz(f) >> 3)
#define frame_sized(f)		(frame_ftsz(f) & ~FRAME_TYPEP)

enum { LJ_CONT_TAILCALL, LJ_CONT_FFI_CALLBACK };  /* Special continuations. */

#define frame_contpc(f)		(frame_pc((f)-2))
#define frame_contv(f)		(((f)-3)->u64)
#define frame_contf(f)		((ASMFunction)(uintptr_t)((f)-3)->u64)
#define frame_iscont_fficb(f)   (frame_contv(f) == LJ_CONT_FFI_CALLBACK)

#define frame_prevl(f)		((f) - (1+LJ_FR2+bc_a(frame_pc(f)[-1])))
#define frame_prevd(f)		((TValue *)((char *)(f) - frame_sized(f)))
#define frame_prev(f)		(frame_islua(f)?frame_prevl(f):frame_prevd(f))
/* Note: this macro does not skip over FRAME_VARG. */

/* -- C stack frame ------------------------------------------------------- */

/* Macros to access and modify the C stack frame chain. */

/* These definitions must match with the arch-specific *.dasc files. */
#define CFRAME_OFS_PREV		(4*8)
#define CFRAME_OFS_PC		(3*8)
#define CFRAME_OFS_L		(2*8)
#define CFRAME_OFS_ERRF		(3*4)
#define CFRAME_OFS_NRES		(2*4)
#define CFRAME_OFS_MULTRES	(0*4)
#define CFRAME_SIZE		(12*8)
#define CFRAME_SIZE_JIT		(CFRAME_SIZE + 16)
#define CFRAME_SHIFT_MULTRES	0

#ifndef CFRAME_SIZE_JIT
#define CFRAME_SIZE_JIT		CFRAME_SIZE
#endif

#define CFRAME_RESUME		1
#define CFRAME_UNWIND_FF	2  /* Only used in unwinder. */
#define CFRAME_RAWMASK		(~(intptr_t)(CFRAME_RESUME|CFRAME_UNWIND_FF))

#define cframe_errfunc(cf)	(*(int32_t *)(((char *)(cf))+CFRAME_OFS_ERRF))
#define cframe_nres(cf)		(*(int32_t *)(((char *)(cf))+CFRAME_OFS_NRES))
#define cframe_prev(cf)		(*(void **)(((char *)(cf))+CFRAME_OFS_PREV))
#define cframe_multres(cf)  (*(uint32_t *)(((char *)(cf))+CFRAME_OFS_MULTRES))
#define cframe_multres_n(cf)	(cframe_multres((cf)) >> CFRAME_SHIFT_MULTRES)
#define cframe_L(cf) \
  (&gcref(*(GCRef *)(((char *)(cf))+CFRAME_OFS_L))->th)
#define cframe_pc(cf) \
  (mref(*(MRef *)(((char *)(cf))+CFRAME_OFS_PC), const BCIns))
#define setcframe_L(cf, L) \
  (setmref(*(MRef *)(((char *)(cf))+CFRAME_OFS_L), (L)))
#define setcframe_pc(cf, pc) \
  (setmref(*(MRef *)(((char *)(cf))+CFRAME_OFS_PC), (pc)))
#define cframe_canyield(cf)	((intptr_t)(cf) & CFRAME_RESUME)
#define cframe_unwind_ff(cf)	((intptr_t)(cf) & CFRAME_UNWIND_FF)
#define cframe_raw(cf)		((void *)((intptr_t)(cf) & CFRAME_RAWMASK))
#define cframe_Lpc(L)		cframe_pc(cframe_raw(L->cframe))

#endif
