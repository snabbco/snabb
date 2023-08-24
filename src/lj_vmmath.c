/*
** Math helper functions for assembler VM.
** Copyright (C) 2005-2022 Mike Pall. See Copyright Notice in luajit.h
*/

#define lj_vmmath_c
#define LUA_CORE

#include <errno.h>
#include <math.h>

#include "lj_obj.h"
#include "lj_ir.h"
#include "lj_vm.h"

/* -- Wrapper functions --------------------------------------------------- */


/* -- Helper functions ---------------------------------------------------- */

/* Required to prevent the C compiler from applying FMA optimizations.
**
** Yes, there's -ffp-contract and the FP_CONTRACT pragma ... in theory.
** But the current state of C compilers is a mess in this regard.
** Also, this function is not performance sensitive at all.
*/
LJ_NOINLINE static double lj_vm_floormul(double x, double y)
{
  return lj_vm_floor(x / y) * y;
}

double lj_vm_foldarith(double x, double y, int op)
{
  switch (op) {
  case IR_ADD - IR_ADD: return x+y; break;
  case IR_SUB - IR_ADD: return x-y; break;
  case IR_MUL - IR_ADD: return x*y; break;
  case IR_DIV - IR_ADD: return x/y; break;
  case IR_MOD - IR_ADD: return x-lj_vm_floormul(x, y); break;
  case IR_POW - IR_ADD: return pow(x, y); break;
  case IR_NEG - IR_ADD: return -x; break;
  case IR_ABS - IR_ADD: return fabs(x); break;
  case IR_LDEXP - IR_ADD: return ldexp(x, (int)y); break;
  case IR_MIN - IR_ADD: return x < y ? x : y; break;
  case IR_MAX - IR_ADD: return x > y ? x : y; break;
  default: return x;
  }
}

/* -- Helper functions for generated machine code ------------------------- */

int32_t lj_vm_modi(int32_t a, int32_t b)
{
  uint32_t y, ua, ub;
  lj_assertX(b != 0, "modulo with zero divisor");
  ua = a < 0 ? ~(uint32_t)a+1u : (uint32_t)a;
  ub = b < 0 ? ~(uint32_t)b+1u : (uint32_t)b;
  y = ua % ub;
  if (y != 0 && (a^b) < 0) y = y - ub;
  if (((int32_t)y^b) < 0) y = ~y+1u;
  return (int32_t)y;
}


#ifdef LUAJIT_NO_LOG2
double lj_vm_log2(double a)
{
  return log(a) * 1.4426950408889634074;
}
#endif

/* Computes fpm(x) for extended math functions. */
double lj_vm_foldfpm(double x, int fpm)
{
  switch (fpm) {
  case IRFPM_FLOOR: return lj_vm_floor(x);
  case IRFPM_CEIL: return lj_vm_ceil(x);
  case IRFPM_TRUNC: return lj_vm_trunc(x);
  case IRFPM_SQRT: return sqrt(x);
  case IRFPM_LOG: return log(x);
  case IRFPM_LOG2: return lj_vm_log2(x);
  default: lj_assertX(0, "bad fpm %d", fpm);
  }
  return 0;
}

int lj_vm_errno(void)
{
  return errno;
}

