/*
** Target architecture selection.
** Copyright (C) 2005-2017 Mike Pall. See Copyright Notice in luajit.h
*/

#ifndef _LJ_ARCH_H
#define _LJ_ARCH_H

#include "lua.h"

/* Target endianess. */
#define LUAJIT_LE	0
#define LUAJIT_BE	1

/* Target architectures. */
#define LUAJIT_ARCH_X86		1
#define LUAJIT_ARCH_x86		1
#define LUAJIT_ARCH_X64		2
#define LUAJIT_ARCH_x64		2
#define LUAJIT_ARCH_ARM		3
#define LUAJIT_ARCH_arm		3
#define LUAJIT_ARCH_ARM64	4
#define LUAJIT_ARCH_arm64	4
#define LUAJIT_ARCH_PPC		5
#define LUAJIT_ARCH_ppc		5
#define LUAJIT_ARCH_MIPS	6
#define LUAJIT_ARCH_mips	6
#define LUAJIT_ARCH_MIPS32	6
#define LUAJIT_ARCH_mips32	6
#define LUAJIT_ARCH_MIPS64	7
#define LUAJIT_ARCH_mips64	7

/* Target OS. */
#define LUAJIT_OS_OTHER		0
#define LUAJIT_OS_WINDOWS	1
#define LUAJIT_OS_LINUX		2
#define LUAJIT_OS_OSX		3
#define LUAJIT_OS_BSD		4
#define LUAJIT_OS_POSIX		5

/* Select native target if no target defined. */

/* Select native OS if no target OS defined. */

/* Set target OS properties. */
#define LJ_OS_NAME	"Linux"

#define LJ_TARGET_WINDOWS	(LUAJIT_OS == LUAJIT_OS_WINDOWS)
#define LJ_TARGET_LINUX		(LUAJIT_OS == LUAJIT_OS_LINUX)
#define LJ_TARGET_OSX		(LUAJIT_OS == LUAJIT_OS_OSX)
#define LJ_TARGET_IOS		(LJ_TARGET_OSX && (LUAJIT_TARGET == LUAJIT_ARCH_ARM || LUAJIT_TARGET == LUAJIT_ARCH_ARM64))
#define LJ_TARGET_POSIX		(LUAJIT_OS > LUAJIT_OS_WINDOWS)
#define LJ_TARGET_DLOPEN	LJ_TARGET_POSIX






/* Set target architecture properties. */

#define LJ_ARCH_NAME		"x64"
#define LJ_ARCH_BITS		64
#define LJ_ARCH_ENDIAN		LUAJIT_LE
#define LJ_ABI_WIN		0
#define LJ_TARGET_X64		1
#define LJ_TARGET_X86ORX64	1
#define LJ_TARGET_EHRETREG	0
#define LJ_TARGET_JUMPRANGE	31	/* +-2^31 = +-2GB */
#define LJ_TARGET_MASKSHIFT	1
#define LJ_TARGET_MASKROT	1
#define LJ_TARGET_UNALIGNED	1
#define LJ_TARGET_GC64		1


#ifndef LJ_PAGESIZE
#define LJ_PAGESIZE		4096
#endif

/* Check for minimum required compiler versions. */
#if defined(__GNUC__)
#if __GNUC__ < 4
#error "Need at least GCC 4.0 or newer"
#endif
#endif

/* Check target-specific constraints. */
#ifndef _BUILDVM_H
#if __USING_SJLJ_EXCEPTIONS__
#error "Need a C compiler with native exception handling on x64"
#endif
#endif

/* 64 bit GC references. */
#define LJ_GC64			1

/* 2-slot frame info. */
#define LJ_FR2			1

/* Disable or enable the JIT compiler. */
#if defined(LUAJIT_DISABLE_JIT) || defined(LJ_ARCH_NOJIT) || defined(LJ_OS_NOJIT)
#define LJ_HASJIT		0
#else
#define LJ_HASJIT		1
#endif

/* Disable or enable the FFI extension. */
#define LJ_HASFFI		1

#ifndef LJ_ARCH_HASFPU
#define LJ_ARCH_HASFPU		1
#endif
#define LJ_ABI_SOFTFP		0
#define LJ_SOFTFP		(!LJ_ARCH_HASFPU)

#if LJ_ARCH_ENDIAN == LUAJIT_BE
#define LJ_LE			0
#define LJ_BE			1
#define LJ_ENDIAN_SELECT(le, be)	be
#define LJ_ENDIAN_LOHI(lo, hi)		hi lo
#else
#define LJ_LE			1
#define LJ_BE			0
#define LJ_ENDIAN_SELECT(le, be)	le
#define LJ_ENDIAN_LOHI(lo, hi)		lo hi
#endif

#define LJ_32			0
#define LJ_64			1

#ifndef LJ_TARGET_UNALIGNED
#define LJ_TARGET_UNALIGNED	0
#endif

/* Compatibility with Lua 5.1 vs. 5.2. */
#ifdef LUAJIT_ENABLE_LUA52COMPAT
#define LJ_52			1
#else
#define LJ_52			0
#endif

#endif
