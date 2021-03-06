/*
 * ui/keys.c
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
 * @brief User Interface initialization and message dispatch
 */
#include <osZ.h>

extern char _binary_logo_start;
extern void keymap_parse(bool_t alt, char *keymap, size_t len);

public void opentty(){}
public void openwin(){}
public void openwrd(){}

void _init()
{
    uint64_t bss = BSS_ADDRESS;
    uint64_t len;

    /* map keymap */
    len = mapfile((void*)bss, "/etc/kbd/en_us");
    keymap_parse(0, (char*)bss, (size_t)len);
    bss += (len + __PAGESIZE-1) & ~(__PAGESIZE-1);

    /* serve requests */
    mq_dispatch();
}
