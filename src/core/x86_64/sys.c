/*
 * core/x86_64/sys.c
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
 * @brief System process
 */

#include "platform.h"
#include "../env.h"

extern OSZ_pmm pmm;
extern uint64_t pt;
extern uint64_t *irq_dispatch_table;
extern uint64_t sys_mapping;

/* Initialize the "system" process */
void sys_init()
{
    // this is so early, we don't have initrd in fs process' bss yet.
    // so we have to rely on identity mapping to locate the files
    uint64_t *paging = (uint64_t *)&tmpmap;
    int i=0, s;
    OSZ_tcb *tcb = (OSZ_tcb*)(pmm.bss_end);
    pid_t pid = thread_new("system");
    subsystems[SRV_system] = pid;
    sys_mapping = tcb->memroot;

    // map device driver dispatcher
    service_loadelf("sbin/system");
    // allocate and map irq dispatcher table
    for(i=0;paging[i]!=0;i++);
    irq_dispatch_table = NULL;
    s = ((ISR_NUMIRQ * nrirqmax * sizeof(void*))+__PAGESIZE-1)/__PAGESIZE;
    // failsafe
    if(s<1)
        s=1;
#if DEBUG
    if(s>1)
        kprintf("core warning: irq_dispatch_table bigger than a page\n");
#endif
    // allocate IRQ Dispatch Table
    while(s--) {
        uint64_t t = (uint64_t)pmm_alloc();
        if(irq_dispatch_table == NULL) {
            irq_dispatch_table = (uint64_t*)t;
            irq_dispatch_table[0] = nrirqmax;
        }
        paging[i++] = t + PG_USER_RO;
    }
    // map libc
    service_loadso("lib/libc.so");
    // detect devices and load drivers (sharedlibs) for them
    dev_init();

    // dynamic linker
    service_rtlink();
    irq_dispatch_table = NULL;
    // modify TCB for system task, platform specific part
    tcb->priority = PRI_SYS;
    //set IOPL=3 in rFlags
    tcb->rflags |= (3<<12);

    // add to queue so that scheduler will know about this thread
    sched_add(pid);
}
