/*
** FFI C call handling.
** Copyright (C) 2005-2017 Mike Pall. See Copyright Notice in luajit.h
*/

#ifndef _LJ_CCALL_H
#define _LJ_CCALL_H

#include "lj_obj.h"
#include "lj_ctype.h"


/* -- C calling conventions ----------------------------------------------- */


#define CCALL_NARG_GPR		6
#define CCALL_NARG_FPR		8
#define CCALL_NRET_GPR		2
#define CCALL_NRET_FPR		2
#define CCALL_VECTOR_REG	1	/* Pass vectors in registers. */

#define CCALL_SPS_FREE		1
#define CCALL_ALIGN_CALLSTATE	16

typedef LJ_ALIGN(16) union FPRArg {
  double d[2];
  float f[4];
  uint8_t b[16];
  uint16_t s[8];
  int i[4];
  int64_t l[2];
} FPRArg;

typedef intptr_t GPRArg;


#ifndef CCALL_SPS_EXTRA
#define CCALL_SPS_EXTRA		0
#endif
#ifndef CCALL_VECTOR_REG
#define CCALL_VECTOR_REG	0
#endif
#ifndef CCALL_ALIGN_STACKARG
#define CCALL_ALIGN_STACKARG	1
#endif
#ifndef CCALL_ALIGN_CALLSTATE
#define CCALL_ALIGN_CALLSTATE	8
#endif

#define CCALL_NUM_GPR \
  (CCALL_NARG_GPR > CCALL_NRET_GPR ? CCALL_NARG_GPR : CCALL_NRET_GPR)
#define CCALL_NUM_FPR \
  (CCALL_NARG_FPR > CCALL_NRET_FPR ? CCALL_NARG_FPR : CCALL_NRET_FPR)

/* Check against constants in lj_ctype.h. */
LJ_STATIC_ASSERT(CCALL_NUM_GPR <= CCALL_MAX_GPR);
LJ_STATIC_ASSERT(CCALL_NUM_FPR <= CCALL_MAX_FPR);

#define CCALL_MAXSTACK		32

/* -- C call state -------------------------------------------------------- */

typedef LJ_ALIGN(CCALL_ALIGN_CALLSTATE) struct CCallState {
  void (*func)(void);		/* Pointer to called function. */
  uint32_t spadj;		/* Stack pointer adjustment. */
  uint8_t nsp;			/* Number of stack slots. */
  uint8_t retref;		/* Return value by reference. */
  uint8_t ngpr;			/* Number of arguments in GPRs. */
  uint8_t nfpr;			/* Number of arguments in FPRs. */
#if CCALL_NUM_FPR
  FPRArg fpr[CCALL_NUM_FPR];	/* Arguments/results in FPRs. */
#endif
  GPRArg gpr[CCALL_NUM_GPR];	/* Arguments/results in GPRs. */
  GPRArg stack[CCALL_MAXSTACK];	/* Stack slots. */
} CCallState;

/* -- C call handling ----------------------------------------------------- */

/* Really belongs to lj_vm.h. */
LJ_ASMF void lj_vm_ffi_call(CCallState *cc);

LJ_FUNC CTypeID lj_ccall_ctid_vararg(CTState *cts, cTValue *o);
LJ_FUNC int lj_ccall_func(lua_State *L, GCcdata *cd);


#endif
