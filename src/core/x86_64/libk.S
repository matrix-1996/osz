/*
 * core/x86_64/libk.S
 *
 * Copyright 2017 CC-by-nc-sa bztsrc@github
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
 * @brief low level kernel routines for the core
 */

.section .text
.global kpanic
.global kmemcpy
.global kmemmove
.global kmemset
.global kmemcmp
.global kmemvid
.global kmap
.global kmap_init
.global kmap_mq
.global kmap_getpte
.global kstrcpy
.global kstrlen
.global kstrcmp
.global ksend
.global kwaitkey
.extern kmap_tmp
.extern tmpctrl
.extern tmpmqctrl
.extern tmppte
.extern mq_mapping
.extern kpanicprefix
.extern kpanicsuffix
.extern kpanicsuffix2
.extern sys_fault

/* kernel panic */
kpanic:
    movq    %rsp, %rbp
    pushq   %rdi
    pushq   %rsi
    pushq   %rdx
    call    kprintf_reset
    /* clear the first line */
    movl    $0xFFDD33, fg
    movl    $0, bg
    movq    $kpanicprefix, %rdi
    call    kprintf
    popq    %rdx
    popq    %rsi
    popq    %rdi
    addq    $8, %rsp
    call    kprintf
    movq    __PAGESIZE-40, %rsi
    /* canonized url? */
    movq    %rsi, %rax
    shrq    $48, %rax
    cmpw    $0xFFFF, %ax
    je      1f
    orw     %ax, %ax
    jnz     2f
    /* if so, print rip and try to resolve symbol for it */
1:  movq    $kpanicrip, %rdi
    call    kprintf
    movq    __PAGESIZE-40, %rdi
    call    service_sym
    mov     %rax, %rsi
    movq    $kpanicsym, %rdi
    call    kprintf
2:
#if DEBUG
    movb    $13, %dil
    call    dbg_putchar
    movb    $10, %dil
    call    dbg_putchar
    cmpb    $0, dbg_enabled
    jz      1f
    movq    $theme_panic, dbg_theme
    movq    __PAGESIZE-40, %rdi
    movq    %rbp, %rsi
    xorq    %rdx, %rdx
    call    dbg_enable
    jmp     2f
1:
#endif
    movq    $54, %rdi
    movq    $5, %rsi
    call    kprintf_center
    push    kx
    movl    $0x9c3c1b, fg
    movl    $0x100000, bg
    movq    $kpanicsuffix, %rdi
    call    kprintf
    movl    $0x500000, fg
    movq    $kpanicsuffix2, %rdi
    call    kprintf
    pop     kx
    addl    $46, kx
    addl    $1, ky
    call    kprintf_putlogo
    /* wait for user input */
    call    kwaitkey
    /* reboot computer */
2:  mov     $0xFE, %al
    out     %al, $0x64
    hlt

/* misc memory functions */
kmemcpy:
    movq    %rdx, %rcx
    repnz   movsb
    ret

kmemmove:
    addq    %rcx, %rdi
    addq    %rcx, %rsi
    movq    %rdx, %rcx
    std
    repnz   movsb
    cld
    ret

kmemset:
    movb    %sil, %al
    movq    %rdx, %rcx
    repnz   stosb
    ret

kmemcmp:
    pushq   %rdi
    xorq    %rax, %rax
    incl    %edx
1:  decl    %edx
    jz      3f
    lodsb
    cmpb    $0, sys_fault
    jnz     3f
    or      %al, %al
    jnz     2f
    cmpb    $0, (%rdi)
    je      3f
    cmpb    $0, sys_fault
    jnz     3f
    incb    %al
    jmp     3f
2:  subb    (%rdi), %al
    incq    %rdi
    or      %al, %al
    jz      1b
3:  popq    %rdi
    ret

kstrcpy:
1:  lodsb
    stosb
    or      %al, %al
    jnz     1b
    movq    %rdi, %rax
    ret

kstrlen:
    movq    %rdi, %rsi
    xor     %rcx, %rcx
    decq    %rcx
1:  lodsb
    incq    %rcx
    or      %al, %al
    jnz     1b
    movq    %rcx, %rax
    ret

kstrcmp:
    xorq    %rax, %rax
1:  lodsb
    cmpb    %al, (%rdi)
    jne     2f
    incq    %rdi
    or      %al, %al
    jnz     1b
2:  ret

kmap:
    call    kmap_getpte
    andw    $0xF000, %si
    mov     %dl, %sil
    /* copy W bit to NX bit */
    andb    $2, %dl
    shlq    $62, %rdx
    addq    %rdx, %rsi
    movq    %rsi, (%rax)
    invlpg  (%rdi)
    ret

kmap_init:
    push    %rbx
    push    %rcx
    /* this is called very early. Relies on identity mapping
       to find the physical address of tmppte pointer in PTE */
    movq    $tmppte, %rcx
    /* PML4 */
    movq    %rcx, %rbx
    shrq    $12+9+9+9, %rbx
    andl    $0x1FF, %ebx
    shlq    $3, %rbx
    movq    %cr3, %rax
    andw    $0xF000, %ax
    movq    %rax, identity_mapping
    add     %rax, %rbx
    /* save core mapping pointer */
    addq    $__PAGESIZE-8, %rax
    movq    (%rax), %rax
    movq    %rax, core_mapping
    /* PDPE */
    movq    (%rbx), %rax
    xorb    %al, %al
    movq    %rcx, %rbx
    shrq    $12+9+9, %rbx
    andl    $0x1FF, %ebx
    shlq    $3, %rbx
    add     %rax, %rbx
    /* PDE */
    movq    (%rbx), %rax
    xorb    %al, %al
    movq    %rcx, %rbx
    shrq    $12+9, %rbx
    andl    $0x1FF, %ebx
    shlq    $3, %rbx
    add     %rax, %rbx
    /* save TMPQ_ADDRESS mapping pointer */
    movb    $PG_CORE_NOCACHE, %al
    movq    %rax, %r8
    /* PTE */
    movq    (%rbx), %rax
    xorb    %al, %al
    movq    %rcx, %rbx
    shrq    $12, %rbx
    andl    $0x1FF, %ebx
    shlq    $3, %rbx
    add     %rax, %rbx
    /* map it at tmppte */
    mov     %rbx, %rax
    addq    $8, %rax
    movq    %rax, %rdi
    andw    $0xF000, %ax
    incw    %ax
    mov     %rax, (%rbx)
    /* map TMPQ_ADDRESS pde at tmpmqctrl */
    addq    $8, %rbx
    mov     %r8, (%rbx)
    /* record pointer at kmap_tmp */
    subq    $24, %rbx
    andq    $0x0FFF, %rbx
    addq    %rcx, %rbx
    movq    %rbx, %rax
    popq    %rcx
    popq    %rbx
    ret

/* map a message queue temporairly
   IN rdi: tcb->self */
kmap_mq:
    pushq   %rdi
    movb    $PG_CORE_NOCACHE, %dil
    movq    $tmpmqctrl, %rax
    addq    $__PAGESIZE-16, %rax
    movq    %rdi, (%rax)
    movq    $TMPQ_ADDRESS, %rax
    movw    nrmqmax, %cx
1:  invlpg  (%rax)
    addq    $__PAGESIZE, %rax
    decw    %cx
    jnz     1b
    popq    %rsi
    movq    $tmp2map, %rdi
    movb    $PG_CORE_NOCACHE, %sil
    call    kmap
    ret

/* IN rdi: virtual address
 * OUT rax: address of page entry in PT */
kmap_getpte:
    /* we have tmpctrl, so we can map PTE */
    movq    kmap_tmp, %r10
    xorq    %r9, %r9
    /* PML4 */
    movq    %rdi, %rax
    shrq    $12+9+9+9, %rax
    andl    $0x1FF, %eax
    shlq    $3, %rax
    movq    %cr3, %rdx
    andw    $0xF000, %dx
    incw    %dx
    movq    %rdx, (%r10)
    invlpg  tmpctrl
    addq    $tmpctrl, %rax
    incb    %r9b
    /* PDPE */
    mov     (%rax), %rdx
    movq    %rdi, %rax
    shrq    $12+9+9, %rax
    andl    $0x1FF, %eax
    shlq    $3, %rax
    andw    $0xF000, %dx
    orq     %rdx, %rdx
    jz      1f
    incw    %dx
    movq    %rdx, (%r10)
    invlpg  tmpctrl
    addq    $tmpctrl, %rax
    incb    %r9b
    /* PDE */
    mov     (%rax), %rdx
    movq    %rdi, %rax
    shrq    $12+9, %rax
    andl    $0x1FF, %eax
    shlq    $3, %rax
    andw    $0xF000, %dx
    orq     %rdx, %rdx
    jz      1f
    incw    %dx
    movq    %rdx, (%r10)
    invlpg  tmpctrl
    addq    $tmpctrl, %rax
    incb    %r9b
    /* PTE */
    mov     (%rax), %rdx
    movq    %rdi, %rax
    shrq    $12, %rax
    andl    $0x1FF, %eax
    shlq    $3, %rax
    andw    $0xF000, %dx
    orq     %rdx, %rdx
    jz      1f
    incw    %dx
    movq    %rdx, (%r10)
    invlpg  tmpctrl
    addq    $tmpctrl, %rax
    ret
1:  movq    %r9, %rdx
    movq    %rdi, %rsi
    movq    $kpanictlb, %rdi
    call    kpanic

/* send a message to a message queue. This has to be effective
   and I didn't like the code gcc generated, that's why it's
   asm, otherwise this routine is not platform specific.
    IN: rdi: mq, rsi: event, rdx: arg0, rcx: arg1, r8: arg2
    OUT: true on success
*/
ksend:
    /* check if message queue is full */
    movq    (%rdi), %rax
    /* mqhdr->mq_start+1 == mqhdr->mq_end? */
    incq    %rax
    cmpq    8(%rdi), %rax
    je      1f
    /* mqhdr->mq_start+1 == mqhdr->mq_size && mqhdr->mq_end==1? */
    cmpq    16(%rdi), %rax
    jne      2f
    cmpq    $1, 8(%rdi)
    jne     2f
1:  /* we won't block if we're sending to system thread,
       rather remove the last item from the message queue
       to make space and we continue */
    movq    %rsi, %rax
    /* destination pid == -1 ? */
    shrq    $16, %rax
    cmpl    $SRV_SYS, %eax
    jne     4f
    /* mqhdr->mq_end++ */
    incq    8(%rdi)
    movq    8(%rdi), %rax
    cmpq    16(%rdi), %rax
    jne     2f
    movq    $1, 8(%rdi)
2:  /* replace destination pid with sender's */
    andq    $0xFFFF, %rsi
    /* tcb.mypid<<16 */
    movq    tcb_mypid, %rax
    shlq    $16, %rax
    orq     %rax, %rsi
    /* copy message */
    movq    (%rdi), %rax
    shlq    $6, %rax
    addq    %rdi, %rax
    movq    %rsi, (%rax)
    movq    %rdx, 8(%rax)
    movq    %rcx, 16(%rax)
    movq    %r8, 24(%rax)
    movq    16(%rbp), %r9
    movq    %r9, 32(%rax)
    movq    24(%rbp), %r9
    movq    %r9, 40(%rax)
    movq    32(%rbp), %r9
    movq    %r9, 48(%rax)
    movq    $sysinfostruc, %r9
    addq    $sysinfo_ticks, %r9
    movq    (%r9), %r9
    movq    %r9, 56(%rax)
    /* mqhdr->mq_start++ */
    incq    (%rdi)
    movq    (%rdi), %rax
    cmpq    16(%rdi), %rax
    jne     3f
    movq    $1, (%rdi)
3:  xorq    %rax, %rax
    incb    %al
    ret
4:  xorq    %rax, %rax
    ret

/* an early implementation, called by kprintf */
kwaitkey:
    xorq    %rax, %rax
    xorq    %rdx, %rdx
    /* is there a key waiting? */
1:  inb     $0x64, %al
    andb    $1, %al
    jnz     2f
    pause
#if DEBUG
    movw    $0x3fd, %dx
    inb     %dx, %al
    /* do we have a serial port at all? */
    cmpb    $0xFF, %al
    je      1b
    /* is there a received byte waiting? */
    andb    $1, %al
    jz      1b
    subb    $5, %dl
    inb     %dx, %al
    orb     %al, %al
    jz      1b
    movb    $0, dbg_iskbd
    jmp     8f
#else
    jmp     1b
#endif
    /* yes, read the scancode */
2:  inb     $0x60, %al
    orb     %al, %al
    jz      1b
    movb    %al, %dl
    /* acknowledge */
    inb     $0x61, %al
    outb    %al, $0x61
#if DEBUG
    /* handle shift key here for debugger */
    movb    $1, dbg_iskbd
    cmpb    $54, %dl
    je      2f
    cmpb    $42, %dl
    jne     1f
2:  movb    $1, dbg_isshft
    jmp     3f
1:  cmpb    $54+0x80, %dl
    je      2f
    cmpb    $42+0x80, %dl
    jne     3f
2:  movb    $0, dbg_isshft
3:
#endif
    /* check extended scancode */
    cmpb    $0xE0, %dl
    jne     1f
    movb    $1, 9f
    jmp     kwaitkey
1:  cmpb    $0xE1, %dl
    jne     1f
    movb    $2, 9f
    jmp     kwaitkey
1:  cmpb    $0xFF, %dl
    jne     1f
    movb    $3, 9f
    jmp     kwaitkey
1:  xorq    %rax, %rax
    movb    9f, %ah
    movb    $0, 9f
    movb    %dl, %al
    bt      $7, %ax
    jc      kwaitkey
8:  /* extended scancode in ax */
    ret
9:
    .byte 0
