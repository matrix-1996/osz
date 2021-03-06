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

extern sysinfo_t sysinfostruc;

phy_t __attribute__ ((section (".data"))) sys_mapping;
phy_t __attribute__ ((section (".data"))) core_mapping;
phy_t __attribute__ ((section (".data"))) identity_mapping;
phy_t __attribute__ ((section (".data"))) *stack_ptr;

/* create a thread, allocate memory for it and init TCB */
pid_t thread_new(char *cmdline)
{
    OSZ_tcb *tcb = (OSZ_tcb*)(pmm.bss_end);
    uint64_t *paging = (uint64_t *)&tmpmap, self;
    void *ptr, *ptr2;
    uint i;

    /* allocate at least 1 page for message queue */
    if(nrmqmax<1)
        nrmqmax=1;

    /* allocate TCB */
    ptr=pmm_alloc();
    kmap((uint64_t)pmm.bss_end, (uint64_t)ptr, PG_CORE_NOCACHE);
    tcb->magic = OSZ_TCB_MAGICH;
    tcb->state = tcb_state_running;
    tcb->priority = PRI_APP;
    self = (uint64_t)ptr;
    tcb->mypid = (pid_t)(self/__PAGESIZE);
    tcb->allocmem = 8 + nrmqmax;
    tcb->cs = 0x20+3; // ring 3 user code
    tcb->ss = 0x18+3; // ring 3 user data
    tcb->rflags = 0x202; // enable interrupts and mandatory bit 1

    /* allocate memory mappings */
    // PML4
    ptr=pmm_alloc();
    tcb->memroot = (uint64_t)ptr;
    kmap((uint64_t)&tmpmap, (uint64_t)ptr, PG_CORE_NOCACHE);
    // PDPE
    ptr=pmm_alloc();
    paging[0]=(uint64_t)ptr+PG_USER_RW;
    paging[511]=(core_mapping&~(__PAGESIZE-1))+PG_CORE;
    kmap((uint64_t)&tmpmap, (uint64_t)ptr, PG_CORE_NOCACHE);
    // PDE
    ptr=pmm_alloc();
    paging[0]=(uint64_t)ptr+PG_USER_RW;
    kmap((uint64_t)&tmpmap, (uint64_t)ptr, PG_CORE_NOCACHE);
    // PT text
    ptr=pmm_alloc();
    //pt=(uint64_t)ptr;
    paging[0]=((uint64_t)ptr+PG_USER_RW)|((uint64_t)1<<63);
    ptr2=pmm_alloc();
    paging[1]=(uint64_t)ptr2+PG_USER_RW;
    kmap((uint64_t)&tmpmap, (uint64_t)ptr, PG_CORE_NOCACHE);
    // map TCB
    tcb->self = (uint64_t)ptr;
    paging[0]=(self+PG_USER_RO)|((uint64_t)1<<63);
    // allocate message queue
    for(i=0;i<nrmqmax;i++) {
        ptr=pmm_alloc();
        paging[i+(MQ_ADDRESS/__PAGESIZE)]=((uint64_t)ptr+PG_USER_RW)|((uint64_t)1<<63);
    }
    // allocate stack
    ptr=pmm_alloc();
    paging[511]=((uint64_t)ptr+PG_USER_RW)|((uint64_t)1<<63);
    // we don't need the table any longer, so we can use it to map the
    // message queue header for initialization
    kmap((uint64_t)&tmpmap, (uint64_t)(paging[(MQ_ADDRESS/__PAGESIZE)]&~(__PAGESIZE-1)), PG_CORE_NOCACHE);
    msghdr_t *msghdr = (msghdr_t *)&tmpmap;
    msghdr->mq_start = msghdr->mq_end = 1;
    msghdr->mq_size = (nrmqmax*__PAGESIZE)/sizeof(msg_t);
    msghdr->mq_buffstart = msghdr->mq_buffend = msghdr->mq_buffmin = (nrmqmax+1);
    msghdr->mq_buffsize = __SLOTSIZE/__PAGESIZE/2;
    // set up stack, watch out for alignment
    kmap((uint64_t)&tmpmap, (uint64_t)ptr, PG_CORE_NOCACHE);
    i = 511-((kstrlen(cmdline)+2+15)/16*2);
    tcb->name = TEXT_ADDRESS - __PAGESIZE + i*8;
    kstrcpy((char*)(&paging[i--]), cmdline);
    paging[i--] = 0;                                 // argv[1]
    paging[i] = TEXT_ADDRESS-__PAGESIZE+(i+2)*8;i--; // argv[0]
    paging[i] = TEXT_ADDRESS-__PAGESIZE+(i+1)*8;i--; // argv
    paging[i--] = 1;                                 // argc
    stack_ptr = ptr + i*8;
    tcb->rsp = tcb->cmdline = TEXT_ADDRESS - __PAGESIZE + (i+1)*8;
    // map text segment mapping for elf loading
    kmap((uint64_t)&tmpmap, (uint64_t)ptr2, PG_CORE_NOCACHE);
#if DEBUG
    if(sysinfostruc.debug&DBG_THREADS||sysinfostruc.debug==DBG_ELF)
        kprintf("Thread %x %s\n",self/__PAGESIZE,cmdline);
#endif
    return self/__PAGESIZE;
}

bool_t thread_check(OSZ_tcb *tcb, phy_t *paging)
{
    return true;
}

bool_t thread_allowed(char *grp, uint8_t access)
{
    OSZ_tcb *tcb = (OSZ_tcb*)(0);
    char *g;
    int i,j;
    if(grp==NULL||grp[0]==0)
        return false;
    j=kstrlen(grp);
    if(j>15)
        j=15;
    for(i=0;i<TCB_MAXACE;i++) {
        g = (char *)(&tcb->acl[i]);
        if(g[0]==0)
            return false;
        if(!kmemcmp(g, grp, j))
            return (g[15] & access)!=0;
    }
    return false;
}
