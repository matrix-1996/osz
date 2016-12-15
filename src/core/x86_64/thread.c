/*
 * core/x86_64/thread.c
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
 * @brief Thread functions platform dependent code
 */

#include "../core.h"
#include "../pmm.h"
#include "tcb.h"
#include <elf.h>
#include <fsZ.h>

/* external resources */
extern uint8_t tmpmap;
extern uint8_t tmp2map;
extern uint8_t identity_map;
extern uint8_t MQ_ADDRESS;
extern uint nrmqmax;
extern void *pmm_alloc();
extern void *fs_locate(char *fn);
extern void *fs_mapelf(char *fn);

uint64_t __attribute__ ((section (".data"))) core_mapping;
uint64_t __attribute__ ((section (".data"))) shlib_mapping;
uint64_t __attribute__ ((section (".data"))) fullsize;

pid_t thread_new()
{
    OSZ_tcb *newtcb,*tcb = (OSZ_tcb*)&tmp2map;
    uint64_t *paging = (uint64_t *)&tmp2map, self;
    void *ptr, *ptr2;
    uint i;

    /* allocate at least 1 page for message queue */
    if(nrmqmax<1)
        nrmqmax=1;

    /* allocate TCB */
    newtcb=pmm_alloc();
    kmap((uint64_t)&tmp2map, (uint64_t)newtcb, PG_CORE_NOCACHE);
    tcb->magic = OSZ_TCB_MAGICH;
    tcb->state = tcb_running;
    tcb->priority = PRI_SRV;
    self = (uint64_t)newtcb+1;
    tcb->allocmem = 7 + nrmqmax;
    tcb->evtq_ptr = tcb->evtq_endptr = (OSZ_event*)&MQ_ADDRESS;

    /* allocate memory mappings */
    // PML4
    ptr=pmm_alloc();
    tcb->memroot = (uint64_t)ptr;
    kmap((uint64_t)&tmp2map, (uint64_t)ptr, PG_CORE_NOCACHE);
    // PDPE
    ptr=pmm_alloc();
    paging[0]=(uint64_t)ptr+1;
    paging[511]=core_mapping;
    kmap((uint64_t)&tmp2map, (uint64_t)ptr, PG_CORE_NOCACHE);
    // PDE
    ptr=pmm_alloc();
    paging[0]=(uint64_t)ptr+1;
    // PT shared libs
    ptr2=pmm_alloc();
    paging[1]=(uint64_t)ptr2+1;
    kmap((uint64_t)&tmp2map, (uint64_t)ptr2, PG_CORE_NOCACHE);
    shlib_mapping=(uint64_t)pmm_alloc();
    paging[0]=shlib_mapping+1;
    kmap((uint64_t)&tmp2map, (uint64_t)ptr, PG_CORE_NOCACHE);
    // PT text
    ptr=pmm_alloc();
    paging[0]=(uint64_t)ptr+1;
    ptr2=pmm_alloc();
    paging[1]=(uint64_t)ptr2+1;
    kmap((uint64_t)&tmp2map, (uint64_t)ptr, PG_CORE_NOCACHE);
    // map TCB, relies on identity mapping
    newtcb->self = (uint64_t)ptr;
    paging[0]=self;
    // allocate message queue
    for(i=0;i<nrmqmax;i++) {
        ptr=pmm_alloc();
        paging[i+((uint64_t)&MQ_ADDRESS/__PAGESIZE)]=(uint64_t)ptr+1;
    }
    // map text segment mapping for elf loading
    kmap((uint64_t)&tmp2map, (uint64_t)ptr2, PG_CORE_NOCACHE);
kprintf("tcb=%x\n",newtcb->self);
    return (uint64_t)newtcb/__PAGESIZE;
}

/* load an ELF64 executable into text segment at 2M */
void *thread_loadelf(char *fn)
{
    uint64_t *paging = (uint64_t *)&tmp2map;
    void *elf;
    if(identity_map){
        elf=(void *)fs_locate(fn);
    }else{
        elf=fs_mapelf(fn);
    }
    int i,ret,size=(fs_size+__PAGESIZE-1)/__PAGESIZE;
    if(elf==NULL)
        return NULL;
    // relocate and map. PT at tmp2map
    while((paging[i]&1)!=0 && i<1024-size) i++;
    if((paging[i]&1)!=0) {
        kpanic("thread_loadelf: Out of memory");
    }
    ret = i;
#if DEBUG
    kprintf("loadelf(%s) %x:%d @%d\n",fn,elf,size,ret);
#endif
    while(size--) {
        paging[i]=(uint64_t)(elf + (i-ret)*__PAGESIZE+1);
        i++;
    }
    fullsize += size;
    return (void*)((uint64_t)ret * __PAGESIZE);
}

/* load an ELF64 shared object into text segment at 4G */
void thread_loadso(char *fn)
{
    // map SHLIB_ADDRESS' PT at tmp2map
    kmap((uint64_t)&tmp2map, shlib_mapping, PG_CORE_NOCACHE);
    thread_loadelf(fn);
//    uint64_t *paging = (uint64_t *)&tmp2map;
//    Elf64_Ehdr *ehdr=(Elf64_Ehdr *)(thread_loadelf(fn) + SHLIB_ADDRESS);
// TODO: relocate if returned address is not zero
}

// add a TCB to priority queue
void thread_add(pid_t thread)
{
    // uint64_t ptr = thread * __PAGESIZE;
}

// remove a TCB from priority queue
void thread_remove(pid_t thread)
{
    // uint64_t ptr = thread * __PAGESIZE;
}

/* Function to start a system service */
void service_init2(char *fn, char *so)
{
    OSZ_tcb *tcb = (OSZ_tcb*)&tmp2map;
    pid_t pid = thread_new();
    fullsize = 0;
    // map executable
    thread_loadelf(fn);
    // map libc
    thread_loadso("lib/libc.so");
    // map additional shared library
    if(so!=NULL)
        thread_loadso(so);
    // modify TCB
    kmap((uint64_t)&tmp2map, (uint64_t)(pid*__PAGESIZE), PG_CORE_NOCACHE);
    tcb->linkmem += fullsize;
    // add to queue so that scheduler will know about this thread
    thread_add(pid);
}

void service_init(char *fn)
{
    service_init2(fn, NULL);
}