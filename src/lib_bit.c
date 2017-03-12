/*
** Bit manipulation library.
** Copyright (C) 2005-2017 Mike Pall. See Copyright Notice in luajit.h
*/

#define lib_bit_c
#define LUA_LIB

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include "lj_obj.h"
#include "lj_err.h"
#include "lj_buf.h"
#include "lj_strscan.h"
#include "lj_strfmt.h"
#include "lj_ctype.h"
#include "lj_cdata.h"
#include "lj_cconv.h"
#include "lj_carith.h"
#include "lj_ff.h"
#include "lj_lib.h"

/* ------------------------------------------------------------------------ */

#define LJLIB_MODULE_bit

static int bit_result64(lua_State *L, CTypeID id, uint64_t x)
{
  GCcdata *cd = lj_cdata_new_(L, id, 8);
  *(uint64_t *)cdataptr(cd) = x;
  setcdataV(L, L->base-1-LJ_FR2, cd);
  return FFH_RES(1);
}

LJLIB_ASM(bit_tobit)		LJLIB_REC(bit_tobit)
{
  CTypeID id = 0;
  setintV(L->base-1-LJ_FR2, (int32_t)lj_carith_check64(L, 1, &id));
  return FFH_RES(1);
}

LJLIB_ASM(bit_bnot)		LJLIB_REC(bit_unary IR_BNOT)
{
  CTypeID id = 0;
  uint64_t x = lj_carith_check64(L, 1, &id);
  return id ? bit_result64(L, id, ~x) : FFH_RETRY;
}

LJLIB_ASM(bit_bswap)		LJLIB_REC(bit_unary IR_BSWAP)
{
  CTypeID id = 0;
  uint64_t x = lj_carith_check64(L, 1, &id);
  return id ? bit_result64(L, id, lj_bswap64(x)) : FFH_RETRY;
}

LJLIB_ASM(bit_lshift)		LJLIB_REC(bit_shift IR_BSHL)
{
  CTypeID id = 0, id2 = 0;
  uint64_t x = lj_carith_check64(L, 1, &id);
  int32_t sh = (int32_t)lj_carith_check64(L, 2, &id2);
  if (id) {
    x = lj_carith_shift64(x, sh, curr_func(L)->c.ffid - (int)FF_bit_lshift);
    return bit_result64(L, id, x);
  }
  if (id2) setintV(L->base+1, sh);
  return FFH_RETRY;
}
LJLIB_ASM_(bit_rshift)		LJLIB_REC(bit_shift IR_BSHR)
LJLIB_ASM_(bit_arshift)		LJLIB_REC(bit_shift IR_BSAR)
LJLIB_ASM_(bit_rol)		LJLIB_REC(bit_shift IR_BROL)
LJLIB_ASM_(bit_ror)		LJLIB_REC(bit_shift IR_BROR)

LJLIB_ASM(bit_band)		LJLIB_REC(bit_nary IR_BAND)
{
  CTypeID id = 0;
  TValue *o = L->base, *top = L->top;
  int i = 0;
  do { lj_carith_check64(L, ++i, &id); } while (++o < top);
  if (id) {
    CTState *cts = ctype_cts(L);
    CType *ct = ctype_get(cts, id);
    int op = curr_func(L)->c.ffid - (int)FF_bit_bor;
    uint64_t x, y = op >= 0 ? 0 : ~(uint64_t)0;
    o = L->base;
    do {
      lj_cconv_ct_tv(cts, ct, (uint8_t *)&x, o, 0);
      if (op < 0) y &= x; else if (op == 0) y |= x; else y ^= x;
    } while (++o < top);
    return bit_result64(L, id, y);
  }
  return FFH_RETRY;
}
LJLIB_ASM_(bit_bor)		LJLIB_REC(bit_nary IR_BOR)
LJLIB_ASM_(bit_bxor)		LJLIB_REC(bit_nary IR_BXOR)

/* ------------------------------------------------------------------------ */

LJLIB_CF(bit_tohex)		LJLIB_REC(.)
{
  CTypeID id = 0, id2 = 0;
  uint64_t b = lj_carith_check64(L, 1, &id);
  int32_t n = L->base+1>=L->top ? (id ? 16 : 8) :
				  (int32_t)lj_carith_check64(L, 2, &id2);
  SBuf *sb = lj_buf_tmp_(L);
  SFormat sf = (STRFMT_UINT|STRFMT_T_HEX);
  if (n < 0) { n = -n; sf |= STRFMT_F_UPPER; }
  sf |= ((SFormat)((n+1)&255) << STRFMT_SH_PREC);
  if (n < 16) b &= ((uint64_t)1 << 4*n)-1;
  sb = lj_strfmt_putfxint(sb, sf, b);
  setstrV(L, L->top-1, lj_buf_str(L, sb));
  lj_gc_check(L);
  return 1;
}

/* ------------------------------------------------------------------------ */

#include "lj_libdef.h"

LUALIB_API int luaopen_bit(lua_State *L)
{
  LJ_LIB_REG(L, LUA_BITLIBNAME, bit);
  return 1;
}

