/*
 * stdarg.h
 *
 * Copyright 2016 CC-by-nc-sa bztsrc@github
 * https://creativecommons.org/licenses/by-nc-sa/4.0/
 *
 * You are free to:
 *
 * - Share — copy and redistribute the material in any medium or format
 * - Adapt — remix, transform, and build upon the material
 *     The licensor cannot revoke these freedoms as long as you follow
 *     the license terms.
 *
 * Under the following terms:
 *
 * - Attribution — You must give appropriate credit, provide a link to
 *     the license, and indicate if changes were made. You may do so in
 *     any reasonable manner, but not in any way that suggests the
 *     licensor endorses you or your use.
 * - NonCommercial — You may not use the material for commercial purposes.
 * - ShareAlike — If you remix, transform, or build upon the material,
 *     you must distribute your contributions under the same license as
 *     the original.
 *
 * @brief variable length arguments
 */

#ifndef _STDARG_H_
#define _STDARG_H_ 1

typedef void *va_list;

#ifdef __builtin_va_start
#define va_start(list, param) __builtin_va_start(list, param)
#else
//TODO: this is x86_64 ABI specific
#define va_start(list, param) (list = (((va_list)&param) + sizeof(void*)*4))
#endif

#ifdef __builtin_va_arg
#define va_arg(list, type)    __builtin_va_arg(list, type)
#else
#define va_arg(list, type)    (*(type *)((list += sizeof(void*)) - sizeof(void*)))
#endif

#endif /* stdarg.h */
