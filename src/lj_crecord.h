/*
** Trace recorder for C data operations.
** Copyright (C) 2005-2017 Mike Pall. See Copyright Notice in luajit.h
*/

#ifndef _LJ_CRECORD_H
#define _LJ_CRECORD_H

#include "lj_obj.h"
#include "lj_jit.h"
#include "lj_ffrecord.h"

LJ_FUNC void recff_cdata_index(jit_State *J, RecordFFData *rd);
LJ_FUNC void recff_cdata_call(jit_State *J, RecordFFData *rd);
LJ_FUNC void recff_cdata_arith(jit_State *J, RecordFFData *rd);
LJ_FUNC void recff_clib_index(jit_State *J, RecordFFData *rd);
LJ_FUNC void recff_ffi_new(jit_State *J, RecordFFData *rd);
LJ_FUNC void recff_ffi_errno(jit_State *J, RecordFFData *rd);
LJ_FUNC void recff_ffi_string(jit_State *J, RecordFFData *rd);
LJ_FUNC void recff_ffi_copy(jit_State *J, RecordFFData *rd);
LJ_FUNC void recff_ffi_fill(jit_State *J, RecordFFData *rd);
LJ_FUNC void recff_ffi_typeof(jit_State *J, RecordFFData *rd);
LJ_FUNC void recff_ffi_istype(jit_State *J, RecordFFData *rd);
LJ_FUNC void recff_ffi_abi(jit_State *J, RecordFFData *rd);
LJ_FUNC void recff_ffi_xof(jit_State *J, RecordFFData *rd);
LJ_FUNC void recff_ffi_gc(jit_State *J, RecordFFData *rd);

LJ_FUNC void recff_bit64_tobit(jit_State *J, RecordFFData *rd);
LJ_FUNC int recff_bit64_unary(jit_State *J, RecordFFData *rd);
LJ_FUNC int recff_bit64_nary(jit_State *J, RecordFFData *rd);
LJ_FUNC int recff_bit64_shift(jit_State *J, RecordFFData *rd);
LJ_FUNC TRef recff_bit64_tohex(jit_State *J, RecordFFData *rd, TRef hdr);

LJ_FUNC void lj_crecord_tonumber(jit_State *J, RecordFFData *rd);

#endif
