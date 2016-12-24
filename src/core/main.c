/*
 * core/main.c
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
 * @brief Core, boot environment
 *
 *   Memory map
 *       -512M framebuffer                      (0xFFFFFFFFE0000000)
 * 
 *       -2M core        bootboot[2] struct     (0xFFFFFFFFFFE00000)
 *         -2M + 1page   environment[3]         (0xFFFFFFFFFFE01000)
 *         -2M + 2page.. core text segment v    (0xFFFFFFFFFFE02000)
 *         -2M + Xpage.. core bss          v    (0xFFFFFFFFFFExxxxx)
 *         ..0           core boot stack   ^    (0x0000000000000000)

 *       0-16G user      RAM identity mapped[4] (0x0000000000000000)
 * 
 *   [1] see msg_t in msg.h
 *   [2] see loader/bootboot.h
 *   [3] see etc/CONFIG and env.h. Plain ascii key=value pairs,
 *       separated by whitespace characters. Filled up with spaces
 *       to page size.
 *   [4] when main() calls isr_enable(), user thread will be mapped
 *       instead into 0 - 2^56 and shared memory in -2^56 - -512M.
 */

#include "env.h"
extern OSZ_pmm pmm;

/**********************************************************************
 *                         OS/Z Life Cycle                            *
 **********************************************************************
*/
void main()
{
    kprintf("OS/Z starting... %x\n", bootboot.datetime);

    /* step 1: motoric reflexes */
    // check processor capabilities
    cpu_init();
    // parse environment
    env_init();
    // initialize physical memory manager, required by new thread creation
    pmm_init();

    // this is early, we don't have "fs" subsystem yet.

    // initialize the "system" task, service_init(SRV_system, "sbin/system")
    // In addition this will detect device drivers
    sys_init();
    // interrupt service routines (idt), initialize CCB. Has to be done
    // after sys_init(), as it may require addresses from parsed tables
    isr_init();
    // initialize "fs" task, special service_init(SRV_fs, "sbin/fs")
    fs_init();

    /* step 2: communication */
    // initialize "ui" task to handle user input / output
    service_init(SRV_ui, "sbin/ui");
    if(networking) {
        // initialize "net" task for ipv4 and ipv6 routing
        service_init(SRV_net, "sbin/net");
    }
    if(sound) {
        // initialize "sound" task to handle audio channels
        service_init(SRV_sound, "sbin/sound");
    }

    /* step 3: historic memory */
    // start "syslog" task so others can log errors
    service_init(SRV_syslog, "sbin/syslog");

    /* step 4: who am I */
    fs_locate("etc/hostname");
    if(identity || fs_size==0) {
        // start first time turn on's set up task
        service_init(USER_PROCESS, "sbin/identity");
    }

    /* step 5: stand up and prosper. */
    // load "init" or "sh" process
    service_init(USER_PROCESS, rescueshell ? "bin/sh" : "sbin/init");

    // started message
    kprintf("OS/Z ready. Allocated %d pages out of %d.\n",
        pmm.totalpages - pmm.freepages, pmm.totalpages);
    // scroll out "starting" message
    kprintf_reset(); kprintf_scrollscr();

    // enable interrupts. After the first IRQ the
    // scheduler will choose a thread to run and we...
    isr_enable();
    // ...should not reach this code ever. Instead sched_pick() will
    // call dev_poweroff() when no tasks left after shutdown.

    /* step 6: go to dreamless sleep. */
    //dev_poweroff();
}