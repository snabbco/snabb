/*
** LuaJIT common internal definitions.
** Copyright (C) 2005-2023 Mike Pall. See Copyright Notice in luajit.h
*/

#ifndef _LJ_DEF_H
#define _LJ_DEF_H

#include "lua.h"

#include <stdint.h>

/* Needed everywhere. */
#include <string.h>
#include <stdlib.h>

/* Various VM limits. */
#define LJ_MAX_MEM32	0x7fffff00	/* Max. 32 bit memory allocation. */
#define LJ_MAX_MEM64	((uint64_t)1<<47)  /* Max. 64 bit memory allocation. */
/* Max. total memory allocation. */
#define LJ_MAX_MEM	LJ_MAX_MEM64
#define LJ_MAX_ALLOC	LJ_MAX_MEM	/* Max. individual allocation length. */
#define LJ_MAX_STR	LJ_MAX_MEM32	/* Max. string length. */
#define LJ_MAX_BUF	LJ_MAX_MEM32	/* Max. buffer length. */
#define LJ_MAX_UDATA	LJ_MAX_MEM32	/* Max. userdata length. */

#define LJ_MAX_STRTAB	(1<<26)		/* Max. string table size. */
#define LJ_MAX_HBITS	26		/* Max. hash bits. */
#define LJ_MAX_ABITS	28		/* Max. bits of array key. */
#define LJ_MAX_ASIZE	((1<<(LJ_MAX_ABITS-1))+1)  /* Max. array part size. */
#define LJ_MAX_COLOSIZE	16		/* Max. elems for colocated array. */

#define LJ_MAX_LINE	LJ_MAX_MEM32	/* Max. source code line number. */
#define LJ_MAX_XLEVEL	200		/* Max. syntactic nesting level. */
#define LJ_MAX_BCINS	(1<<26)		/* Max. # of bytecode instructions. */
#define LJ_MAX_SLOTS	250		/* Max. # of slots in a Lua func. */
#define LJ_MAX_LOCVAR	200		/* Max. # of local variables. */
#define LJ_MAX_UPVAL	60		/* Max. # of upvalues. */

#define LJ_MAX_IDXCHAIN	100		/* __index/__newindex chain limit. */
#define LJ_STACK_EXTRA	(5+2*LJ_FR2)	/* Extra stack space (metamethods). */

#define LJ_NUM_CBPAGE	1		/* Number of FFI callback pages. */

/* Minimum table/buffer sizes. */
#define LJ_MIN_GLOBAL	6		/* Min. global table size (hbits). */
#define LJ_MIN_REGISTRY	2		/* Min. registry size (hbits). */
#define LJ_MIN_STRTAB	256		/* Min. string table size (pow2). */
#define LJ_MIN_SBUF	32		/* Min. string buffer length. */
#define LJ_MIN_VECSZ	8		/* Min. size for growable vectors. */
#define LJ_MIN_IRSZ	32		/* Min. size for growable IR. */

/* JIT compiler limits. */
#define LJ_MAX_JSLOTS	250		/* Max. # of stack slots for a trace. */
#define LJ_MAX_PHI	64		/* Max. # of PHIs for a loop. */
#define LJ_MAX_EXITSTUBGR	16	/* Max. # of exit stub groups. */

/* Various macros. */
#ifndef UNUSED
#define UNUSED(x)	((void)(x))	/* to avoid warnings */
#endif

#define U64x(hi, lo)	(((uint64_t)0x##hi << 32) + (uint64_t)0x##lo)
#define i32ptr(p)	((int32_t)(intptr_t)(void *)(p))
#define u32ptr(p)	((uint32_t)(intptr_t)(void *)(p))
#define i64ptr(p)	((int64_t)(intptr_t)(void *)(p))
#define u64ptr(p)	((uint64_t)(intptr_t)(void *)(p))
#define igcptr(p)	i64ptr(p)

#define checki8(x)	((x) == (int32_t)(int8_t)(x))
#define checku8(x)	((x) == (int32_t)(uint8_t)(x))
#define checki16(x)	((x) == (int32_t)(int16_t)(x))
#define checku16(x)	((x) == (int32_t)(uint16_t)(x))
#define checki32(x)	((x) == (int32_t)(x))
#define checku32(x)	((x) == (uint32_t)(x))
#define checkptr32(x)	((uintptr_t)(x) == (uint32_t)(uintptr_t)(x))
#define checkptr47(x)	(((uint64_t)(uintptr_t)(x) >> 47) == 0)
#define checkptrGC(x)	checkptr47((x))

/* Every half-decent C compiler transforms this into a rotate instruction. */
#define lj_rol(x, n)	(((x)<<(n)) | ((x)>>(-(int)(n)&(8*sizeof(x)-1))))
#define lj_ror(x, n)	(((x)<<(-(int)(n)&(8*sizeof(x)-1))) | ((x)>>(n)))

/* A really naive Bloom filter. But sufficient for our needs. */
typedef uintptr_t BloomFilter;
#define BLOOM_MASK	(8*sizeof(BloomFilter) - 1)
#define bloombit(x)	((uintptr_t)1 << ((x) & BLOOM_MASK))
#define bloomset(b, x)	((b) |= bloombit((x)))
#define bloomtest(b, x)	((b) & bloombit((x)))

#if defined(__GNUC__) || defined(__clang__) || defined(__psp2__)

#define LJ_NORET	__attribute__((noreturn))
#define LJ_ALIGN(n)	__attribute__((aligned(n)))
#define LJ_INLINE	inline
#define LJ_AINLINE	inline __attribute__((always_inline))
#define LJ_NOINLINE	__attribute__((noinline))

#if defined(__ELF__) || defined(__MACH__) || defined(__psp2__)
#define LJ_NOAPI	extern __attribute__((visibility("hidden")))
#endif

/* Note: it's only beneficial to use fastcall on x86 and then only for up to
** two non-FP args. The amalgamated compile covers all LJ_FUNC cases. Only
** indirect calls and related tail-called C functions are marked as fastcall.
*/

#define LJ_LIKELY(x)	__builtin_expect(!!(x), 1)
#define LJ_UNLIKELY(x)	__builtin_expect(!!(x), 0)

#define lj_ffs(x)	((uint32_t)__builtin_ctz(x))
#define lj_fls(x)	((uint32_t)(__builtin_clz(x)^31))
#define lj_ffs64(x)	((uint32_t)__builtin_ctzll(x))
#define lj_fls64(x)	((uint32_t)(__builtin_clzll(x)^63))

#if   (__GNUC__ > 4) || (__GNUC__ == 4 && __GNUC_MINOR__ >= 3) || __clang__
static LJ_AINLINE uint32_t lj_bswap(uint32_t x)
{
  return (uint32_t)__builtin_bswap32((int32_t)x);
}

static LJ_AINLINE uint64_t lj_bswap64(uint64_t x)
{
  return (uint64_t)__builtin_bswap64((int64_t)x);
}
#elif defined(__i386__) || defined(__x86_64__)
static LJ_AINLINE uint32_t lj_bswap(uint32_t x)
{
  uint32_t r; __asm__("bswap %0" : "=r" (r) : "0" (x)); return r;
}

static LJ_AINLINE uint64_t lj_bswap64(uint64_t x)
{
  uint64_t r; __asm__("bswap %0" : "=r" (r) : "0" (x)); return r;
}
#else
static LJ_AINLINE uint32_t lj_bswap(uint32_t x)
{
  return (x << 24) | ((x & 0xff00) << 8) | ((x >> 8) & 0xff00) | (x >> 24);
}

static LJ_AINLINE uint64_t lj_bswap64(uint64_t x)
{
  return (uint64_t)lj_bswap((uint32_t)(x >> 32)) |
	 ((uint64_t)lj_bswap((uint32_t)x) << 32);
}
#endif

typedef union __attribute__((packed)) Unaligned16 {
  uint16_t u;
  uint8_t b[2];
} Unaligned16;

typedef union __attribute__((packed)) Unaligned32 {
  uint32_t u;
  uint8_t b[4];
} Unaligned32;

/* Unaligned load of uint16_t. */
static LJ_AINLINE uint16_t lj_getu16(const void *p)
{
  return ((const Unaligned16 *)p)->u;
}

/* Unaligned load of uint32_t. */
static LJ_AINLINE uint32_t lj_getu32(const void *p)
{
  return ((const Unaligned32 *)p)->u;
}

#else
#error "missing defines for your compiler"
#endif

/* Optional defines. */
#ifndef LJ_NORET
#define LJ_NORET
#endif
#ifndef LJ_NOAPI
#define LJ_NOAPI	extern
#endif
#ifndef LJ_LIKELY
#define LJ_LIKELY(x)	(x)
#define LJ_UNLIKELY(x)	(x)
#endif

/* Attributes for internal functions. */
#define LJ_DATA		LJ_NOAPI
#define LJ_DATADEF
#define LJ_ASMF		LJ_NOAPI
#define LJ_FUNCA	LJ_NOAPI
#define LJ_FUNC		LJ_NOAPI
#define LJ_FUNC_NORET	LJ_FUNC LJ_NORET
#define LJ_FUNCA_NORET	LJ_FUNCA LJ_NORET
#define LJ_ASMF_NORET	LJ_ASMF LJ_NORET

/* Internal assertions. */
#if defined(LUA_USE_ASSERT) || defined(LUA_USE_APICHECK)
#define lj_assert_check(g, c, ...) \
  ((c) ? (void)0 : \
   (lj_assert_fail((g), __FILE__, __LINE__, __func__, __VA_ARGS__), 0))
#define lj_checkapi(c, ...)	lj_assert_check(G(L), (c), __VA_ARGS__)
#else
#define lj_checkapi(c, ...)	((void)L)
#endif

#ifdef LUA_USE_ASSERT
#define lj_assertG_(g, c, ...)	lj_assert_check((g), (c), __VA_ARGS__)
#define lj_assertG(c, ...)	lj_assert_check(g, (c), __VA_ARGS__)
#define lj_assertL(c, ...)	lj_assert_check(G(L), (c), __VA_ARGS__)
#define lj_assertX(c, ...)	lj_assert_check(NULL, (c), __VA_ARGS__)
#define check_exp(c, e)		(lj_assertX((c), #c), (e))
#else
#define lj_assertG_(g, c, ...)	((void)0)
#define lj_assertG(c, ...)	((void)g)
#define lj_assertL(c, ...)	((void)L)
#define lj_assertX(c, ...)	((void)0)
#define check_exp(c, e)		(e)
#endif

/* Static assertions. */
#define LJ_ASSERT_NAME2(name, line)	name ## line
#define LJ_ASSERT_NAME(line)		LJ_ASSERT_NAME2(lj_assert_, line)
#ifdef __COUNTER__
#define LJ_STATIC_ASSERT(cond) \
  extern void LJ_ASSERT_NAME(__COUNTER__)(int STATIC_ASSERTION_FAILED[(cond)?1:-1])
#else
#define LJ_STATIC_ASSERT(cond) \
  extern void LJ_ASSERT_NAME(__LINE__)(int STATIC_ASSERTION_FAILED[(cond)?1:-1])
#endif

/* PRNG state. Need this here, details in lj_prng.h. */
typedef struct PRNGState {
  uint64_t u[4];
} PRNGState;

#endif
