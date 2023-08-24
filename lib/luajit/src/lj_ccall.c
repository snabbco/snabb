/*
** FFI C call handling.
** Copyright (C) 2005-2022 Mike Pall. See Copyright Notice in luajit.h
*/

#include "lj_obj.h"


#include "lj_gc.h"
#include "lj_err.h"
#include "lj_tab.h"
#include "lj_ctype.h"
#include "lj_cconv.h"
#include "lj_cdata.h"
#include "lj_ccall.h"
#include "lj_trace.h"

/* Target-specific handling of register arguments. */
/* -- POSIX/x64 calling conventions --------------------------------------- */

#define CCALL_HANDLE_STRUCTRET \
  int rcl[2]; rcl[0] = rcl[1] = 0; \
  if (ccall_classify_struct(cts, ctr, rcl, 0)) { \
    cc->retref = 1;  /* Return struct by reference. */ \
    cc->gpr[ngpr++] = (GPRArg)dp; \
  } else { \
    cc->retref = 0;  /* Return small structs in registers. */ \
  }

#define CCALL_HANDLE_STRUCTRET2 \
  int rcl[2]; rcl[0] = rcl[1] = 0; \
  ccall_classify_struct(cts, ctr, rcl, 0); \
  ccall_struct_ret(cc, rcl, dp, ctr->size);

#define CCALL_HANDLE_COMPLEXRET \
  /* Complex values are returned in one or two FPRs. */ \
  cc->retref = 0;

#define CCALL_HANDLE_COMPLEXRET2 \
  if (ctr->size == 2*sizeof(float)) {  /* Copy complex float from FPR. */ \
    *(int64_t *)dp = cc->fpr[0].l[0]; \
  } else {  /* Copy non-contiguous complex double from FPRs. */ \
    ((int64_t *)dp)[0] = cc->fpr[0].l[0]; \
    ((int64_t *)dp)[1] = cc->fpr[1].l[0]; \
  }

#define CCALL_HANDLE_STRUCTARG \
  int rcl[2]; rcl[0] = rcl[1] = 0; \
  if (!ccall_classify_struct(cts, d, rcl, 0)) { \
    cc->nsp = nsp; cc->ngpr = ngpr; cc->nfpr = nfpr; \
    if (ccall_struct_arg(cc, cts, d, rcl, o, narg)) goto err_nyi; \
    nsp = cc->nsp; ngpr = cc->ngpr; nfpr = cc->nfpr; \
    continue; \
  }  /* Pass all other structs by value on stack. */

#define CCALL_HANDLE_COMPLEXARG \
  isfp = 2;  /* Pass complex in FPRs or on stack. Needs postprocessing. */

#define CCALL_HANDLE_REGARG \
  if (isfp) {  /* Try to pass argument in FPRs. */ \
    int n2 = ctype_isvector(d->info) ? 1 : n; \
    if (nfpr + n2 <= CCALL_NARG_FPR) { \
      dp = &cc->fpr[nfpr]; \
      nfpr += n2; \
      goto done; \
    } \
  } else {  /* Try to pass argument in GPRs. */ \
    /* Note that reordering is explicitly allowed in the x64 ABI. */ \
    if (n <= 2 && ngpr + n <= maxgpr) { \
      dp = &cc->gpr[ngpr]; \
      ngpr += n; \
      goto done; \
    } \
  }


#ifndef CCALL_HANDLE_STRUCTRET2
#define CCALL_HANDLE_STRUCTRET2 \
  memcpy(dp, sp, ctr->size);  /* Copy struct return value from GPRs. */
#endif

/* -- x86 OSX ABI struct classification ----------------------------------- */


/* -- x64 struct classification ------------------------------------------- */


/* Register classes for x64 struct classification. */
#define CCALL_RCL_INT	1
#define CCALL_RCL_SSE	2
#define CCALL_RCL_MEM	4
/* NYI: classify vectors. */

static int ccall_classify_struct(CTState *cts, CType *ct, int *rcl, CTSize ofs);

/* Classify a C type. */
static void ccall_classify_ct(CTState *cts, CType *ct, int *rcl, CTSize ofs)
{
  if (ctype_isarray(ct->info)) {
    CType *cct = ctype_rawchild(cts, ct);
    CTSize eofs, esz = cct->size, asz = ct->size;
    for (eofs = 0; eofs < asz; eofs += esz)
      ccall_classify_ct(cts, cct, rcl, ofs+eofs);
  } else if (ctype_isstruct(ct->info)) {
    ccall_classify_struct(cts, ct, rcl, ofs);
  } else {
    int cl = ctype_isfp(ct->info) ? CCALL_RCL_SSE : CCALL_RCL_INT;
    lj_assertCTS(ctype_hassize(ct->info),
		 "classify ctype %08x without size", ct->info);
    if ((ofs & (ct->size-1))) cl = CCALL_RCL_MEM;  /* Unaligned. */
    rcl[(ofs >= 8)] |= cl;
  }
}

/* Recursively classify a struct based on its fields. */
static int ccall_classify_struct(CTState *cts, CType *ct, int *rcl, CTSize ofs)
{
  if (ct->size > 16) return CCALL_RCL_MEM;  /* Too big, gets memory class. */
  while (ct->sib) {
    CTSize fofs;
    ct = ctype_get(cts, ct->sib);
    fofs = ofs+ct->size;
    if (ctype_isfield(ct->info))
      ccall_classify_ct(cts, ctype_rawchild(cts, ct), rcl, fofs);
    else if (ctype_isbitfield(ct->info))
      rcl[(fofs >= 8)] |= CCALL_RCL_INT;  /* NYI: unaligned bitfields? */
    else if (ctype_isxattrib(ct->info, CTA_SUBTYPE))
      ccall_classify_struct(cts, ctype_rawchild(cts, ct), rcl, fofs);
  }
  return ((rcl[0]|rcl[1]) & CCALL_RCL_MEM);  /* Memory class? */
}

/* Try to split up a small struct into registers. */
static int ccall_struct_reg(CCallState *cc, CTState *cts, GPRArg *dp, int *rcl)
{
  MSize ngpr = cc->ngpr, nfpr = cc->nfpr;
  uint32_t i;
  UNUSED(cts);
  for (i = 0; i < 2; i++) {
    lj_assertCTS(!(rcl[i] & CCALL_RCL_MEM), "pass mem struct in reg");
    if ((rcl[i] & CCALL_RCL_INT)) {  /* Integer class takes precedence. */
      if (ngpr >= CCALL_NARG_GPR) return 1;  /* Register overflow. */
      cc->gpr[ngpr++] = dp[i];
    } else if ((rcl[i] & CCALL_RCL_SSE)) {
      if (nfpr >= CCALL_NARG_FPR) return 1;  /* Register overflow. */
      cc->fpr[nfpr++].l[0] = dp[i];
    }
  }
  cc->ngpr = ngpr; cc->nfpr = nfpr;
  return 0;  /* Ok. */
}

/* Pass a small struct argument. */
static int ccall_struct_arg(CCallState *cc, CTState *cts, CType *d, int *rcl,
			    TValue *o, int narg)
{
  GPRArg dp[2];
  dp[0] = dp[1] = 0;
  /* Convert to temp. struct. */
  lj_cconv_ct_tv(cts, d, (uint8_t *)dp, o, CCF_ARG(narg));
  if (ccall_struct_reg(cc, cts, dp, rcl)) {
    /* Register overflow? Pass on stack. */
    MSize nsp = cc->nsp, n = rcl[1] ? 2 : 1;
    if (nsp + n > CCALL_MAXSTACK) return 1;  /* Too many arguments. */
    cc->nsp = nsp + n;
    memcpy(&cc->stack[nsp], dp, n*CTSIZE_PTR);
  }
  return 0;  /* Ok. */
}

/* Combine returned small struct. */
static void ccall_struct_ret(CCallState *cc, int *rcl, uint8_t *dp, CTSize sz)
{
  GPRArg sp[2];
  MSize ngpr = 0, nfpr = 0;
  uint32_t i;
  for (i = 0; i < 2; i++) {
    if ((rcl[i] & CCALL_RCL_INT)) {  /* Integer class takes precedence. */
      sp[i] = cc->gpr[ngpr++];
    } else if ((rcl[i] & CCALL_RCL_SSE)) {
      sp[i] = cc->fpr[nfpr++].l[0];
    }
  }
  memcpy(dp, sp, sz);
}

/* -- ARM hard-float ABI struct classification ---------------------------- */


/* -- ARM64 ABI struct classification ------------------------------------- */


/* -- MIPS64 ABI struct classification ---------------------------- */


/* -- Common C call handling ---------------------------------------------- */

/* Infer the destination CTypeID for a vararg argument. */
CTypeID lj_ccall_ctid_vararg(CTState *cts, cTValue *o)
{
  if (tvisnumber(o)) {
    return CTID_DOUBLE;
  } else if (tviscdata(o)) {
    CTypeID id = cdataV(o)->ctypeid;
    CType *s = ctype_get(cts, id);
    if (ctype_isrefarray(s->info)) {
      return lj_ctype_intern(cts,
	       CTINFO(CT_PTR, CTALIGN_PTR|ctype_cid(s->info)), CTSIZE_PTR);
    } else if (ctype_isstruct(s->info) || ctype_isfunc(s->info)) {
      /* NYI: how to pass a struct by value in a vararg argument? */
      return lj_ctype_intern(cts, CTINFO(CT_PTR, CTALIGN_PTR|id), CTSIZE_PTR);
    } else if (ctype_isfp(s->info) && s->size == sizeof(float)) {
      return CTID_DOUBLE;
    } else {
      return id;
    }
  } else if (tvisstr(o)) {
    return CTID_P_CCHAR;
  } else if (tvisbool(o)) {
    return CTID_BOOL;
  } else {
    return CTID_P_VOID;
  }
}

/* Setup arguments for C call. */
static int ccall_set_args(lua_State *L, CTState *cts, CType *ct,
			  CCallState *cc)
{
  int gcsteps = 0;
  TValue *o, *top = L->top;
  CTypeID fid;
  CType *ctr;
  MSize maxgpr, ngpr = 0, nsp = 0, narg;
#if CCALL_NARG_FPR
  MSize nfpr = 0;
#endif

  /* Clear unused regs to get some determinism in case of misdeclaration. */
  memset(cc->gpr, 0, sizeof(cc->gpr));
#if CCALL_NUM_FPR
  memset(cc->fpr, 0, sizeof(cc->fpr));
#endif

  maxgpr = CCALL_NARG_GPR;

  /* Perform required setup for some result types. */
  ctr = ctype_rawchild(cts, ct);
  if (ctype_isvector(ctr->info)) {
    if (!(CCALL_VECTOR_REG && (ctr->size == 8 || ctr->size == 16)))
      goto err_nyi;
  } else if (ctype_iscomplex(ctr->info) || ctype_isstruct(ctr->info)) {
    /* Preallocate cdata object and anchor it after arguments. */
    CTSize sz = ctr->size;
    GCcdata *cd = lj_cdata_new(cts, ctype_cid(ct->info), sz);
    void *dp = cdataptr(cd);
    setcdataV(L, L->top++, cd);
    if (ctype_isstruct(ctr->info)) {
      CCALL_HANDLE_STRUCTRET
    } else {
      CCALL_HANDLE_COMPLEXRET
    }
  }

  /* Skip initial attributes. */
  fid = ct->sib;
  while (fid) {
    CType *ctf = ctype_get(cts, fid);
    if (!ctype_isattrib(ctf->info)) break;
    fid = ctf->sib;
  }

  /* Walk through all passed arguments. */
  for (o = L->base+1, narg = 1; o < top; o++, narg++) {
    CTypeID did;
    CType *d;
    CTSize sz;
    MSize n, isfp = 0, isva = 0;
    void *dp, *rp = NULL;

    if (fid) {  /* Get argument type from field. */
      CType *ctf = ctype_get(cts, fid);
      fid = ctf->sib;
      lj_assertL(ctype_isfield(ctf->info), "field expected");
      did = ctype_cid(ctf->info);
    } else {
      if (!(ct->info & CTF_VARARG))
	lj_err_caller(L, LJ_ERR_FFI_NUMARG);  /* Too many arguments. */
      did = lj_ccall_ctid_vararg(cts, o);  /* Infer vararg type. */
      isva = 1;
    }
    d = ctype_raw(cts, did);
    sz = d->size;

    /* Find out how (by value/ref) and where (GPR/FPR) to pass an argument. */
    if (ctype_isnum(d->info)) {
      if (sz > 8) goto err_nyi;
      if ((d->info & CTF_FP))
	isfp = 1;
    } else if (ctype_isvector(d->info)) {
      if (CCALL_VECTOR_REG && (sz == 8 || sz == 16))
	isfp = 1;
      else
	goto err_nyi;
    } else if (ctype_isstruct(d->info)) {
      CCALL_HANDLE_STRUCTARG
    } else if (ctype_iscomplex(d->info)) {
      CCALL_HANDLE_COMPLEXARG
    } else {
      sz = CTSIZE_PTR;
    }
    sz = (sz + CTSIZE_PTR-1) & ~(CTSIZE_PTR-1);
    n = sz / CTSIZE_PTR;  /* Number of GPRs or stack slots needed. */

    CCALL_HANDLE_REGARG  /* Handle register arguments. */

    /* Otherwise pass argument on stack. */
    if (CCALL_ALIGN_STACKARG && !rp && (d->info & CTF_ALIGN) > CTALIGN_PTR) {
      MSize align = (1u << ctype_align(d->info-CTALIGN_PTR)) -1;
      nsp = (nsp + align) & ~align;  /* Align argument on stack. */
    }
    if (nsp + n > CCALL_MAXSTACK) {  /* Too many arguments. */
    err_nyi:
      lj_err_caller(L, LJ_ERR_FFI_NYICALL);
    }
    dp = &cc->stack[nsp];
    nsp += n;
    isva = 0;

  done:
    if (rp) {  /* Pass by reference. */
      gcsteps++;
      *(void **)dp = rp;
      dp = rp;
    }
    lj_cconv_ct_tv(cts, d, (uint8_t *)dp, o, CCF_ARG(narg));
    /* Extend passed integers to 32 bits at least. */
    if (ctype_isinteger_or_bool(d->info) && d->size < 4) {
      if (d->info & CTF_UNSIGNED)
	*(uint32_t *)dp = d->size == 1 ? (uint32_t)*(uint8_t *)dp :
					 (uint32_t)*(uint16_t *)dp;
      else
	*(int32_t *)dp = d->size == 1 ? (int32_t)*(int8_t *)dp :
					(int32_t)*(int16_t *)dp;
    }
    UNUSED(isva);
    if (isfp == 2 && n == 2 && (uint8_t *)dp == (uint8_t *)&cc->fpr[nfpr-2]) {
      cc->fpr[nfpr-1].d[0] = cc->fpr[nfpr-2].d[1];  /* Split complex double. */
      cc->fpr[nfpr-2].d[1] = 0;
    }
  }
  if (fid) lj_err_caller(L, LJ_ERR_FFI_NUMARG);  /* Too few arguments. */

  cc->nfpr = nfpr;  /* Required for vararg functions. */
  cc->nsp = nsp;
  cc->spadj = (CCALL_SPS_FREE + CCALL_SPS_EXTRA)*CTSIZE_PTR;
  if (nsp > CCALL_SPS_FREE)
    cc->spadj += (((nsp-CCALL_SPS_FREE)*CTSIZE_PTR + 15u) & ~15u);
  return gcsteps;
}

/* Get results from C call. */
static int ccall_get_results(lua_State *L, CTState *cts, CType *ct,
			     CCallState *cc, int *ret)
{
  CType *ctr = ctype_rawchild(cts, ct);
  uint8_t *sp = (uint8_t *)&cc->gpr[0];
  if (ctype_isvoid(ctr->info)) {
    *ret = 0;  /* Zero results. */
    return 0;  /* No additional GC step. */
  }
  *ret = 1;  /* One result. */
  if (ctype_isstruct(ctr->info)) {
    /* Return cdata object which is already on top of stack. */
    if (!cc->retref) {
      void *dp = cdataptr(cdataV(L->top-1));  /* Use preallocated object. */
      CCALL_HANDLE_STRUCTRET2
    }
    return 1;  /* One GC step. */
  }
  if (ctype_iscomplex(ctr->info)) {
    /* Return cdata object which is already on top of stack. */
    void *dp = cdataptr(cdataV(L->top-1));  /* Use preallocated object. */
    CCALL_HANDLE_COMPLEXRET2
    return 1;  /* One GC step. */
  }
#if CCALL_NUM_FPR
  if (ctype_isfp(ctr->info) || ctype_isvector(ctr->info))
    sp = (uint8_t *)&cc->fpr[0];
#endif
#ifdef CCALL_HANDLE_RET
  CCALL_HANDLE_RET
#endif
  /* No reference types end up here, so there's no need for the CTypeID. */
  lj_assertL(!(ctype_isrefarray(ctr->info) || ctype_isstruct(ctr->info)),
	     "unexpected reference ctype");
  return lj_cconv_tv_ct(cts, ctr, 0, L->top-1, sp);
}

/* Call C function. */
int lj_ccall_func(lua_State *L, GCcdata *cd)
{
  CTState *cts = ctype_cts(L);
  CType *ct = ctype_raw(cts, cd->ctypeid);
  CTSize sz = CTSIZE_PTR;
  if (ctype_isptr(ct->info)) {
    sz = ct->size;
    ct = ctype_rawchild(cts, ct);
  }
  if (ctype_isfunc(ct->info)) {
    CCallState cc;
    int gcsteps, ret;
    cc.func = (void (*)(void))cdata_getptr(cdataptr(cd), sz);
    gcsteps = ccall_set_args(L, cts, ct, &cc);
    ct = (CType *)((intptr_t)ct-(intptr_t)cts->tab);
    cts->cb.slot = ~0u;
    lj_vm_ffi_call(&cc);
    if (cts->cb.slot != ~0u) {  /* Blacklist function that called a callback. */
      TValue tv;
      tv.u64 = ((uintptr_t)(void *)cc.func >> 2) | U64x(800000000, 00000000);
      setboolV(lj_tab_set(L, cts->miscmap, &tv), 1);
    }
    ct = (CType *)((intptr_t)ct+(intptr_t)cts->tab);  /* May be reallocated. */
    gcsteps += ccall_get_results(L, cts, ct, &cc, &ret);
    while (gcsteps-- > 0)
      lj_gc_check(L);
    return ret;
  }
  return -1;  /* Not a function. */
}

