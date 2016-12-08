/*
 * core.c
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
 * @brief Core
 *
 *   Memory map
 *       -512M framebuffer                   (0xFFFFFFFFE0000000)
 *       -2M core        bootboot struct     (0xFFFFFFFFFFE00000)
 *           -2M+1page   environment         (0xFFFFFFFFFFE01000)
 *           -2M+2page.. core text segment v (0xFFFFFFFFFFE02000)
 *           -2M+Xpage.. core bss          v
 *            ..0        core stack        ^
 *       0-16G RAM identity mapped
 */

#include "core.h"

/**********************************************************************
 *                         OS/Z Core start                            *
 **********************************************************************
*/
void main()
{
	// initialize kernel implementation of printf
	kprintf_init();
	// parse environment
	env_init();
	// initialize physical memory manager
	pmm_init();
	// interrupt service routines (idt)
	isr_init();

	__asm__ __volatile__ ( "int $1;xchgw %%bx,%%bx;cli;hlt" : : : );

}
