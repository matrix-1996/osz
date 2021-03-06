;*
;* loader/mb-x86_64/bootboot.asm
;*
;* Copyright 2016 Public Domain BOOTBOOT bztsrc@github
;*
;* This file is part of the BOOTBOOT Protocol package.
;* @brief Booting code for BIOS and MultiBoot
;*
;*  2nd stage loader, compatible with GRUB and
;*  BIOS boot specification 1.0.1 too (even expansion ROM).
;*
;*  memory occupied: 800-7C00
;*
;*  Memory map
;*      0h -  600h reserved for the system
;*    600h -  800h stage1 (MBR)
;*    800h - 6C00h stage2 (this)
;*   6C00h - 7C00h stack
;*   8000h - 9000h bootboot structure
;*   9000h - A000h environment
;*   A000h - B000h disk buffer / PML4
;*   B000h - C000h PDPE, higher half core 4K slots
;*   C000h - D000h PDE 4K
;*   D000h - E000h PTE 4K
;*   E000h - F000h PDPE, 4G physical RAM identity mapped 2M
;*   F000h -10000h PDE 2M
;*  10000h -11000h PDE 2M
;*  11000h -12000h PDE 2M
;*  12000h -13000h PDE 2M
;*  13000h -14000h PTE 4K
;*  14000h -15000h core stack
;*
;*  At first big enough free hole, initrd. Usually at 1Mbyte.
;*

;get Core boot parameter block
include "bootboot.inc"

;maximum size of core, 1 page directory, 2M on x86_64
CORE_MAX = 2*1024*1024

;VBE filter (available, has additional info, color, graphic, linear fb)
VBE_MODEFLAGS   equ         1+2+8+16+128

;*********************************************************************
;*                             Macros                                *
;*********************************************************************

;Writes a message on screen.
macro real_print msg
{
if ~ msg eq si
            push        si
            mov         si, msg
end if
            call        real_printfunc
if ~ msg eq si
            pop         si
end if
}

;protected and real mode are functions, because we have to switch beetween
macro       real_protmode
{
            USE16
            call            near real_protmodefunc
            USE32
}

macro       prot_realmode
{
            USE32
            call            near prot_realmodefunc
            USE16
}

;edx:eax sector, edi:pointer
macro       prot_readsector
{
            call            prot_readsectorfunc
}

virtual at 0
    fsdriver.locate_initrd: dw 0
    fsdriver.locate_kernel: dw 0
end virtual

;*********************************************************************
;*                             header                                *
;*********************************************************************
;offs   len desc
;  0     2  expansion ROM magic (AA55h)
;  2     1  size in blocks (40h)
;  3     1  magic E9h
;  4     2  real mode entry point (relative)
;  6     2  checksum
;  8     8  magic 'BOOTBOOT'
; 16    10  zeros, at least one and a padding
; 26     2  pnp ptr, must be zero
; 28     4  flags, must be zero
; 32    32  MultiBoot header with protected mode entry point
;any format can follow.

            USE16
            ORG         800h
;BOOTBOOT stage2 header (64 bytes)
loader:     db          55h,0AAh                ;ROM magic
            db          (loader_end-loader)/512 ;size in 512 blocks
.executor:  jmp         near realmode_start     ;entry point
.checksum:  dw          0                       ;checksum
.name:      db          "BOOTBOOT"
            dw          0
            dd          0, 0
.pnpptr:    dw          0
.flags:     dd          0
MB_MAGIC    equ         01BADB002h
MB_FLAGS    equ         0D43h
            align           8
.mb_header: dd          MB_MAGIC        ;magic
            dd          MB_FLAGS        ;flags
            dd          -(MB_MAGIC+MB_FLAGS)    ;checksum (0-magic-flags)
            dd          .mb_header      ;our location (GRUB should load us here)
            dd          0800h           ;the same... load start
            dd          07C00h          ;load end
            dd          0h              ;no bss
            dd          multiboot_start ;entry point

;no segments or sections, code comes right after the header

;*********************************************************************
;*                             code                                  *
;*********************************************************************

;----------------Multiboot stub-----------------
            USE32
multiboot_start:
            cld
            cli
            lgdt        [GDT_value]
            cmp         eax, 2BADB002h
            je          @f
            ;no GRUB environment available?
            ;something really nasty happened, restart computer
            mov         al, 0FEh
            out         64h, al
            hlt
@@:
            ;save drive code for boot device
            mov         dl, byte [ebx+12]
            prot_realmode
            ;fall into realmode start code

;-----------realmode-protmode stub-------------
realmode_start:
            cli
            cld
            mov         sp, 7C00h
            ;relocate ourself from ROM to RAM if necessary
            call        .getaddr
.getaddr:   pop         si
            mov         ax, cs
            or          ax, ax
            jnz         .reloc
            cmp         si, .getaddr
            je          .noreloc
.reloc:     mov         ds, ax
            xor         ax, ax
            mov         es, ax
            mov         di, loader
            sub         si, .getaddr-loader
            mov         cx, (loader_end-loader)/2
            repnz       movsw
            xor         ax, ax
            mov         ds, ax
            xor         dl, dl
            jmp         0:.noreloc
.noreloc:   or          dl, dl
            jnz         @f
            mov         dl, 80h
@@:         mov         byte [bootdev], dl

            ;-----check CPU-----
            ;at least 286?
            pushf
            pushf
            pop         dx
            xor         dh,40h
            push        dx
            popf
            pushf
            pop         bx
            popf
            cmp         dx, bx
            jne         .cpuerror
            ;check for 386
            ;look for cpuid instruction
            pushfd
            pop         eax
            mov         ebx, eax
            xor         eax, 200000h
            and         ebx, 200000h
            push        eax
            popfd
            pushfd
            pop         eax
            and         eax, 200000h
            xor         eax, ebx
            shr         eax, 21
            and         al, 1
            jz          .cpuerror
            ;ok, now we can get cpu feature flags
            mov         eax, 1
            cpuid
            shr         al, 4
            shr         ebx, 24
            mov         dword [bootboot.bspid], ebx
            ;look for minimum family
            cmp         ax, 0600h
            jb          .cpuerror
            ;look for minimum feature flags
            ;do we have SSE3?
            bt          ecx, 0
            jnc         .cpuerror
            ;and PAE?
            mov         eax, edx
            and         eax, 1000000b
            jz          .cpuok
            ;what about MSR?
            bt          edx, 5
            jnc         .cpuok
            ;and can we use long mode?
            mov         eax, 80000000h
            push        bx
            cpuid
            pop         bx
            cmp         eax, 80000001h
            jb          .cpuok
            mov         eax, 80000001h
            cpuid
            ;long mode
            bt          edx, 29
            jc          .cpuok
.cpuerror:  mov         si, noarch
            jmp         real_diefunc
.cpuok:     ;okay, we can do 64 bit!

            ;-----enable A20-----
            ;no problem even if a20 is already turned on.
            stc
            mov         ax, 2401h   ;BIOS enable A20 function
            int         15h
            jnc         .a20ok
            ;keyboard nightmare
            call        .a20wait
            mov         al, 0ADh
            out         64h, al
            call        .a20wait
            mov         al, 0D0h
            out         64h, al
            call        .a20wait2
            in          al, 60h
            push            ax
            call        .a20wait
            mov         al, 0D1h
            out         64h, al
            call        .a20wait
            pop         ax
            or          al, 2
            out         60h, al
            call        .a20wait
            mov         al, 0AEh
            out         64h, al
            jmp         .a20ok

            ;all methods failed, report an error
            mov         si, a20err
            jmp         real_diefunc

.a20wait:   in          al, 64h
            test        al, 2
            jnz         .a20wait
            ret
.a20wait2:  in          al, 64h
            test        al, 1
            jz          .a20wait2
            ret
.a20ok:

            ;-----detect memory map-----
getmemmap:  xor         eax, eax
            mov         dword [bootboot.acpi_ptr], eax
            mov         dword [bootboot.smbi_ptr], eax
            mov         dword [bootboot.initrd_ptr], eax
            mov         eax, bootboot_MAGIC
            mov         dword [bootboot.magic], eax
            mov         dword [bootboot.size], 128
            mov         dword [bootboot.pagesize], 4096
            mov         dword [bootboot.mmap_ptr], 0FFE00000h + 128
            mov         dword [bootboot.mmap_ptr+4], 0FFFFFFFFh
            mov         di, bootboot.mmap
            mov         cx, 800h
            xor         ax, ax
            repnz       stosw
            mov         di, bootboot.mmap
            xor         ebx, ebx
            clc
.nextmap:   cmp         word [bootboot.size], 4096
            jae         .nomoremap
            mov         edx, 'PAMS'
            xor         ecx, ecx
            mov         cl, 20
            xor         eax, eax
            mov         ax, 0E820h
            int         15h
            jc          .nomoremap
            cmp         eax, 'PAMS'
            jne         .nomoremap
            ;is this the first memory hole? If so, mark
            ;ourself as reserved memory
            cmp         dword [di+4], 0
            jnz         .notfirst
            cmp         dword [di], 0
            jnz         .notfirst
            ; "allocate" memory for loader
            mov         eax, 15000h
            add         dword [di], eax
            sub         dword [di+8], eax
.notfirst:  mov         al, byte [di+16]
            cmp         al, 2
            jne         .noov
            mov         al, 5
            ;hardcoded mmio for VGA and BIOS ROM
            mov         ecx, dword [di]
            cmp         ecx, 0A0000h
            ja          .noov
            add         ecx, dword [di+8]
            cmp         ecx, 0A0000h
            jbe         .noov
            mov         al, 6
.noov:      ;copy memory type to size's least significant byte
            mov         byte [di+8], al
            xor         ecx, ecx
            ;is it ACPI area?
            cmp         al, 3
            jne         .notacpi
            mov         dword [bootboot.acpi_ptr], edi
            jmp         .entryok
            ;is it free slot?
.notacpi:   cmp         al, 1
            jne         .notmax
.freemem:   ;do we have a ramdisk area?
            cmp         dword [bootboot.initrd_ptr], 0
            jnz         .entryok
            ;is it big enough for the core and the ramdisk?
            mov         ebp, INITRD_MAXSIZE*1024*1024 + CORE_MAX
;            add         ebp, 1024*1024-1
            shr         ebp, 20
            shl         ebp, 20
            ;is this free memory hole big enough? (first fit)
.sizechk:   mov         eax, dword [di+8]               ;load size
            xor         al, al
            mov         edx, dword [di+12]
            and         edx, 000FFFFFFh
            or          edx, edx
            jnz         .bigenough
            cmp         eax, ebp
            jb          .entryok
.bigenough: mov         eax, dword [di]
            ; "allocate" initrd
            add         dword [di], ebp
            sub         dword [di+8], ebp
            ;save ramdisk pointer
            mov         dword [bootboot.initrd_ptr], eax
.entryok:   ;get limit of memory
            mov         eax, dword [di+8]               ;load size
            xor         al, al
            mov         edx, dword [di+12]
            add         eax, dword [di]                 ;add base
            adc         edx, dword [di+4]
            and         edx, 000FFFFFFh
.notmax:    add         dword [bootboot.size], 16
            ;bubble up entry if necessary
            push        si
            push        di
.bubbleup:  mov         si, di
            cmp         di, bootboot.mmap
            jbe         .swapdone
            sub         di, 16
            ;order by base asc
            mov         eax, dword [si+4]
            cmp         eax, dword [di+4]
            jb          .swapmodes
            jne         .swapdone
            mov         eax, dword [si]
            cmp         eax, dword [di]
            jae         .swapdone
.swapmodes: push        di
            mov         cx, 16/2
@@:         mov         dx, word [di]
            lodsw
            stosw
            mov         word [si-2], dx
            dec         cx
            jnz         @b
            pop         di
            jmp         .bubbleup
.swapdone:  pop         di
            pop         si
            add         di, 16
            cmp         di, bootboot.mmap+4096
            jae         .nomoremap
.skip:      or          ebx, ebx
            jnz         .nextmap
.nomoremap: cmp         dword [bootboot.size], 128
            jne         .E820ok
.noE820:    mov         si, memerr
            jmp         real_diefunc

.E820ok:    ;check total memory size
            xor         ecx, ecx
            cmp         dword [bootboot.initrd_ptr], ecx
            jnz         .enoughmem
            mov         si, noenmem
            jmp         real_diefunc
.enoughmem:
            ;-----detect system structures-----
.detacpi:   ;do we need that scanning shit?
            mov         eax, dword [bootboot.acpi_ptr]
            or          eax, eax
            jz          @f
            shr         eax, 4
            mov         es, ax
            ;no if E820 map was correct
            cmp         dword [es:0], 'XSDT'
            je          .detsmbi
            cmp         dword [es:0], 'RSDT'
            je          .detsmbi
@@:         inc         dx
            ;get starting address min(EBDA,E0000)
            mov         ah,0C1h
            stc
            int         15h
            mov         bx, es
            jnc         @f
            mov         ax, [ebdaptr]
@@:         cmp         ax, 0E000h
            jb          .acpinext
            mov         ax, 0E000h
            ;detect ACPI ptr
.acpinext:  mov         es, ax
            cmp         dword [es:0], 'RSD '
            jne         .acpinotf
            cmp         dword [es:4], 'PTR '
            jne         .acpinotf
            ;ptr found
            ; do we have XSDT?
            cmp         dword [es:28], 0
            jne         .acpi2
            cmp         dword [es:24], 0
            je          .acpi1
.acpi2:     mov         eax, dword [es:24]
            mov         dword [bootboot.acpi_ptr], eax
            mov         eax, dword [es:28]
            mov         dword [bootboot.acpi_ptr+4], eax
            jmp         .detsmbi
            ; no, fallback to RSDT
.acpi1:     mov         eax, dword [es:16]
@@:         mov         dword [bootboot.acpi_ptr], eax
            jmp         .detsmbi
.acpinotf:  xor         eax, eax
            mov         ax, es
            inc         ax
            cmp         ax, 0A000h
            jne         @f
            add         ax, 03000h
@@:         ;end of 1Mb?
            or          ax, ax
            jnz         .acpinext
            mov         si, noacpi
            jmp         real_diefunc

            ;detect SMBios tables
.detsmbi:   xor         eax, eax
            mov         ax, 0E000h
            xor         dx, dx
.smbnext:   mov         es, ax
            push            ax
            cmp         dword [es:0], '_SM_'
            je          .smbfound
            cmp         dword [es:0], '_MP_'
            jne         .smbnotf
            shl         eax, 4
            mov         ebx, dword [es:4]
            mov         dword [bootboot.mp_ptr], ebx
            bts         dx, 2
            jmp         .smbnotf
.smbfound:  shl         eax, 4
            mov         dword [bootboot.smbi_ptr], eax
            bts         dx, 1
.smbnotf:   pop         ax
            bt          ax, 0
            mov         bx, ax
            and         bx, 03h
            inc         ax
            ;end of 1Mb?
            or          ax, ax
            jnz         .smbnext
            ;restore ruined es
.detend:    push        ds
            pop         es

            ; ------- BIOS date and time -------
            mov         ah, 4
            int         1Ah
            jc          .nobtime
            ;ch century
            ;cl year
            xchg        ch, cl
            mov         word [bootboot.datetime], cx
            ;dh month
            ;dl day
            xchg        dh, dl
            mov         word [bootboot.datetime+2], dx
            mov         ah, 2
            int         1Ah
            jc          .nobtime
            ;ch hour
            ;cl min
            xchg        ch, cl
            mov         word [bootboot.datetime+4], cx
            ;dh sec
            ;dl daylight saving on/off
            xchg        dh, dl
            mov         word [bootboot.datetime+6], dx
.nobtime:

            ;---- enable protmode ----
            cli
            cld
            lgdt        [GDT_value]
            mov         eax, cr0
            or          al, 1
            mov         cr0, eax
            jmp         CODE_PROT:protmode_start

;writes the reason, waits for a key and reboots.
            USE32
prot_diefunc:
            prot_realmode
            USE16
real_diefunc:
            push        si
            real_print  loader.name
            real_print  panic
            pop         si
            call        real_printfunc
            sti
            xor         ax, ax
            int         16h
            mov         al, 0FEh
            out         64h, al
            jmp         far 0FFFFh:0    ;invoke BIOS POST routine

;ds:si zero terminated string to write
real_printfunc:
            lodsb
            or          al, al
            jz          .end
            mov         ah, byte 0Eh
            mov         bx, word 11
            int         10h
            jmp         real_printfunc
.end:       ret

real_protmodefunc:
            cli
            ;get return address
            xor         ebp, ebp
            pop         bp
            mov         dword [hw_stack], esp
            lgdt        [GDT_value]
            mov         eax, cr0        ;enable protected mode
            or          al, 1
            mov         cr0, eax
            jmp         CODE_PROT:.init

            USE32
.init:      mov         ax, DATA_PROT
            mov         ds, ax
            mov         es, ax
            mov         fs, ax
            mov         gs, ax
            mov         ss, ax
            mov         esp, dword [hw_stack]
            jmp         ebp

prot_realmodefunc:
            cli
            ;get return address
            pop         ebp
            ;save stack pointer
            mov         dword [hw_stack], esp
            jmp         CODE_BOOT:.back     ;load 16 bit mode segment into cs
            USE16
.back:      mov         eax, CR0
            and         al, 0FEh        ;switching back to real mode
            mov         CR0, eax
            xor         ax, ax
            mov         ds, ax          ;load registers 2nd turn
            mov         es, ax
            mov         ss, ax
            jmp         0:.back2
.back2:     mov         sp, word [hw_stack]
            sti
            jmp         bp

            USE32
prot_readsectorfunc:
            push        eax
            push        edx
            push        esi
            push        edi
            ;load 8 sectors (1 page) in low memory
            mov         word [lbapacket.count], 8
            mov         dword [lbapacket.sect0], eax
            mov         dword [lbapacket.sect1], edx
            mov         dword [lbapacket.addr], 0A000h
            prot_realmode
            mov         ah, byte 42h
            mov         dl, byte [bootdev]
            mov         esi, lbapacket
            int         13h
            xor         ebx, ebx
            mov         bl, ah
            real_protmode
            pop         edi
            or          edi, edi
            jz          @f
            push        edi
            ;and copy to addr where it wanted to be (maybe in high memory)
            mov         esi, dword [lbapacket.addr]
            mov         ecx, 1024
            repnz       movsd
            pop         edi
@@:         pop         esi
            pop         edx
            pop         eax
            ret

prot_getval:
            cmp         word[esi],'0x'
            je          .hex
            call        prot_dec2bin
            ret
.hex:       add         esi, 2
            call        prot_hex2bin
            ret

prot_hex2bin:
            xor         eax, eax
            xor         ebx, ebx
            xor         edx, edx
@@:         mov         bl, byte [esi]
            cmp         bl, '0'
            jl          @f
            cmp         bl, '9'
            jle         .num
            cmp         bl, 'A'
            jl          @f
            cmp         bl, 'F'
            jg          @f
            sub         bl, 7
.num:       sub         bl, '0'
            shl         eax, 4
            add         eax, ebx
            inc         esi
            jmp         @b
@@:         ret

prot_dec2bin:
            xor         eax, eax
            xor         ebx, ebx
            xor         edx, edx
            mov         ecx, 10
@@:         mov         bl, byte [esi]
            cmp         bl, '0'
            jb          @f
            cmp         bl, '9'
            ja          @f
            mul         ecx
            sub         bl, '0'
            add         eax, ebx
            inc         esi
            jmp         @b
@@:         ret

;IN: eax=str ptr, ecx=length OUT: eax=num
prot_oct2bin:
            push        ebx
            push        edx
            mov         ebx, eax
            xor         eax, eax
            xor         edx, edx
@@:         shl         eax, 3
            mov         dl, byte[ebx]
            sub         dl, '0'
            add         eax, edx
            inc         ebx
            dec         ecx
            jnz         @b
            pop         edx
            pop         ebx
            ret

protmode_start:
            mov         ax, DATA_PROT
            mov         ds, ax
            mov         es, ax
            mov         fs, ax
            mov         gs, ax
            mov         ss, ax
            mov         esp, 7C00h
            
            ; ------- Locate initrd --------
            ; read GPT
.getgpt:    xor         eax, eax
            xor         edx, edx
            xor         edi, edi
            prot_readsector
            mov         esi, 0A000h+512
            cmp         dword [esi], 'EFI '
            je          @f
.nogpt:     mov         si, nogpt
            jmp         prot_diefunc
@@:
            mov         ecx, dword [esi+80]     ;number of entries
            mov         ebx, dword [esi+84]     ;size of one entry
            add         esi, 512
            mov         edx, esi                ;first entry
            ; look for EFI System Partition
            mov         eax, 0C12A7328h
@@:         cmp         dword [esi], eax        ;GUID match?
            je          .loadesp
            bt          word [esi+48], 2        ;or bootable?
            jc          .loadesp
            add         esi, ebx
            dec         ecx
            jnz         @b
            ;no ESP nor bootable partition, use the first one
            mov         esi, edx

            ; load ESP at free memory hole found
.loadesp:   mov         ecx, dword [esi+40]     ;last sector
            mov         eax, dword [esi+32]     ;first sector
            mov         edx, dword [esi+36]
            or          edx, edx
            jnz         .nogpt
            or          ecx, ecx
            jz          .nogpt
            or          eax, eax
            jz          .nogpt
            sub         ecx, eax
            shr         ecx, 3

            mov         edi, dword [bootboot.initrd_ptr]
.loadnext:  push        ecx
            prot_readsector
            pop         ecx
            or          bl, bl
;           jnz         @f
            add         edi, 4096
            add         eax, 8
            dec         ecx
            jnz         .loadnext
@@:
            ;Locate and parse configuration
            ; *_locate_config
            mov         esi, dword [bootboot.initrd_ptr]
            mov         ecx, INITRD_MAXSIZE*1024*1024
            mov         ebx, esi
            add         ebx, ecx
@@:         add         esi, 512
            cmp         dword [esi+0], '// B'
            jne         .no
            cmp         dword [esi+4], 'OOTB'
            jne         .no
            cmp         dword [esi+8], 'OOT '
            jne         .no
            mov         dl, 1
            jmp         @f
.no:        cmp         esi, ebx
            jb          @b
            xor         dl, dl
@@:
            mov         ebx, 09000h
            mov         edi, ebx
            mov         ecx, 1024
            or          dl,dl
            jz          .noconf
            repnz       movsd
            ;parse
            mov         esi, ebx
            jmp         .getnext

.nextvar:   cmp         word[esi], '//'
            jne         @f
            add         esi, 2
.skipcom:   lodsb
            cmp         al, 10
            je          .getnext
            cmp         al, 13
            je          .getnext
            or          al, al
            jz          .parseend
            cmp         esi, 0A000h
            ja          .parseend
            jmp         .skipcom
@@:         cmp         word[esi], '/*'
            jne         @f
.skipcom2:  inc         esi
            cmp         word [esi-2], '*/'
            je          .getnext
            cmp         byte [esi], 0
            jz          .parseend
            cmp         esi, 0A000h
            ja          .parseend
            jmp         .skipcom2

@@:         cmp         dword[esi], 'widt'
            jne         @f
            cmp         word[esi+4], 'h='
            jne         @f
            add         esi, 6
            call        prot_getval
            mov         dword [reqwidth], eax
            jmp         .getnext
@@:         cmp         dword[esi], 'heig'
            jne         @f
            cmp         word[esi+4], 'ht'
            jne         @f
            cmp         byte[esi+6], '='
            jne         @f
            add         esi, 7
            call        prot_getval
            mov         dword [reqheight], eax
            jmp         .getnext
@@:         cmp         dword[esi], 'kern'
            jne         @f
            cmp         word[esi+4], 'el'
            jne         @f
            cmp         byte[esi+6], '='
            jne         @f
            add         esi, 7
            mov         edi, kernel
.copy:      lodsb
            or          al, al
            jz          .copyend
            cmp         al, ' '
            jz          .copyend
            cmp         al, 13
            jbe         .copyend
            cmp         esi, 0A000h
            ja          .copyend
            cmp         edi, loader_end-1
            jae         .copyend
            stosb
            jmp         .copy
.copyend:   xor         al, al
            stosb
            jmp         .getnext
@@:
            inc         esi
.getnext:   cmp         esi, 0A000h
            jae         .parseend
            cmp         byte [esi], 0
            je          .parseend
            cmp         byte [esi], ' '
            je          @b
            cmp         byte [esi], 13
            jbe         @b
            jmp         .nextvar
.noconf:    repnz       stosd
            mov         dword [ebx+0], '// N'
            mov         dword [ebx+4], '/A\n'
.parseend:

            ; locate INITRD in ESP
            ; *_1stpart_initrd
            mov         edx, fsdrivers
.nextfs1:   xor         ebx, ebx
            mov         bx, word [edx]
            or          bx, bx
            jz          .errfs1
            mov         esi, dword [bootboot.initrd_ptr]
            mov         ecx, INITRD_MAXSIZE*1024*1024
            add         ecx, esi
            push        edx
            call        ebx
            pop         edx
            or          ecx, ecx
            jnz         @f
            add         edx, 4
            jmp         .nextfs1
.errfs1:    mov         si, nord
            jmp         prot_diefunc
@@:
            mov         dword [bootboot.initrd_size], ecx
            ; move initrd to initrd_ptr (overwrite fat tables)
            mov         edi, dword [bootboot.initrd_ptr]
            shr         ecx, 2
            repnz       movsd

            ;-----load /lib/sys/core------
            ; *_initrd
            mov         edx, fsdrivers
.nextfs2:   xor         ebx, ebx
            mov         bx, word [edx+2]
            or          bx, bx
            jz          .errfs2
            mov         esi, dword [bootboot.initrd_ptr]
            mov         ecx, dword [bootboot.initrd_size]
            add         ecx, esi
            mov         edi, kernel
            push        edx
            call        ebx
            pop         edx
            or          ecx, ecx
            jnz         .coreok
            add         edx, 4
            jmp         .nextfs2
.errfs3:    mov         si, nocore
            jmp         prot_diefunc
.errfs2:    ; if all drivers failed, search for the first elf executable
            mov         esi, dword [bootboot.initrd_ptr]
            mov         ecx, dword [bootboot.initrd_size]
            add         ecx, esi
            dec         esi
@@:         inc         esi
            cmp         esi, ecx
            jae         .errfs3
            cmp         dword [esi], 5A2F534Fh ; OS/Z magic
            je          .alt
            cmp         dword [esi], 464C457Fh ; ELF magic
            jne         @b
.alt:       cmp         word [esi+4], 0102h ;lsb 64 bit
            jne         @b
            cmp         word [esi+0x38], 0  ;e_phnum > 0
            jz          @b
.coreok:
            ; parse ELF
            cmp         dword [esi], 5A2F534Fh ; OS/Z magic
            je          @f
            cmp         dword [esi], 464C457Fh ; ELF magic
            jne         .badcore
@@:         cmp         word [esi+4], 0102h ;lsb 64 bit, shared object
            je          @f
.badcore:   mov         esi, badcore
            jmp         prot_diefunc
@@:
            mov         ebx, esi
            mov         eax, dword [esi+0x18]
            mov         dword [entrypoint], eax
            mov         eax, dword [esi+0x18+4]
            mov         dword [entrypoint+4], eax
            ;parse ELF binary and save text section address to dword[core_ptr]
            mov         cx, word [esi+0x38]     ; program header entries phnum
            mov         eax, dword [esi+0x20]   ; program header
            add         esi, eax
            sub         esi, 56
            inc         cx
.nextph:    add         esi, 56
            dec         cx
            jz          .badcore
            cmp         word [esi], 1               ; p_type, loadable
            jne         .nextph
            cmp         dword [esi+8], 0            ; p_offset == 0
            jne         .nextph
            cmp         word [esi+22], 0FFFFh       ; p_vaddr == negative address
            jne         .nextph
            ;got it
            mov         dword [core_ptr], ebx

            ; ------- set video resolution -------
            prot_realmode
            xor         ax, ax
            mov         es, ax
            mov         word [vbememsize], ax
            ;get VESA VBE2.0 info
            mov         ax, 4f00h
            mov         di, 0A000h
            mov         dword [di], 'VBE2'
            ;this call requires a big stack
            int         10h
            cmp         ax, 004fh
            je          @f
.viderr:    mov         si, novbe
            jmp         real_diefunc
            ;get video memory size in MiB
@@:         mov         ax, word [0A000h+12h]
            shr         ax, 4
            or          ax, ax
            jnz         @f
            inc         ax
@@:         mov         word [vbememsize], ax
            ;read dword pointer and copy string to 1st 64k
            ;available video modes
@@:         xor         esi, esi
            xor         edi, edi
            mov         si, word [0A000h+0Eh]
            mov         ax, word [0A000h+10h]
            mov         ds, ax
            xor         ax, ax
            mov         es, ax
            mov         di, 0A000h+400h
            mov         cx, 64
@@:         lodsw
            cmp         ax, 0ffffh
            je          @f
            or          ax, ax
            jz          @f
            stosw
            dec         cx
            jnz         @b
@@:         xor         ax, ax
            stosw
            ;iterate on modes
            mov         si, 0A000h+400h
.nextmode:  mov         di, 0A000h+800h
            xor         ax, ax
            mov         word [0A000h+802h], ax  ; vbe mode
            lodsw
            or          ax, ax
            jz          .viderr
            mov         cx, ax
            mov         ax, 4f01h
            push        bx
            push        cx
            push        si
            push        di
            int         10h
            pop         di
            pop         si
            pop         cx
            pop         bx
            cmp         ax, 004fh
            jne         .viderr
            bts         cx, 13
            bts         cx, 14
            mov         ax, word [0A000h+800h]  ; vbe flags
            and         ax, VBE_MODEFLAGS
            cmp         ax, VBE_MODEFLAGS
            jne         .nextmode
            ;check memory model (direct)
            cmp         byte [0A000h+81bh], 6
            jne         .nextmode
            ;check bpp
            cmp         byte [0A000h+819h], 32
            jne         .nextmode
            ;check min width
            mov         ax, word [reqwidth]
            cmp         ax, 640
            ja          @f
            mov         ax, 640
@@:         cmp         word [0A000h+812h], ax
            jne         .nextmode
            ;check min height
            mov         ax, word [reqheight]
            cmp         ax, 400
            ja          @f
            mov         ax, 400
@@:         cmp         word [0A000h+814h], ax
            jb          .nextmode
            ;match? go no further
.match:     mov         ax, word [0A000h+810h]
            mov         word [bootboot.fb_scanline], ax
            mov         ax, word [0A000h+812h]
            mov         word [bootboot.fb_width], ax
            mov         ax, word [0A000h+814h]
            mov         word [bootboot.fb_height], ax
            mov         eax, dword [0A000h+828h]
            mov         dword [bootboot.fb_ptr], eax
            mov         word [bootboot.fb_type],FB_ARGB ; blue offset
            cmp         byte [0A000h+824h], 0
            je          @f
            mov         word [bootboot.fb_type],FB_RGBA
            cmp         byte [0A000h+824h], 8
            je          @f
            mov         word [bootboot.fb_type],FB_ABGR
            cmp         byte [0A000h+824h], 16
            je          @f
            mov         word [bootboot.fb_type],FB_BGRA
@@:         ; set video mode
            mov         bx, cx
            bts         bx, 14 ;flat linear
            mov         ax, 4f02h
            int         10h
            cmp         ax, 004fh
            jne         .viderr

            ;inform firmware that we're about to leave it's realm
            mov         ax, 0EC00h
            mov         bl, 2 ; 64 bit
            int         15h
            real_protmode

            ; -------- paging ---------
            ;map core at higher half of memory
            ;address 0xffffffffffe00000
            xor         eax, eax
            mov         edi, 0A000h
            mov         ecx, (15000h-0A000h)/4
            repnz       stosd

            ;PML4
            mov         edi, 0A000h
            ;pointer to 2M PDPE (first 4G RAM identity mapped)
            mov         dword [edi], 0E001h
            ;pointer to 4k PDPE (core mapped at -2M)
            mov         dword [edi+4096-8], 0B001h

            ;4K PDPE
            mov         edi, 0B000h
            mov         dword [edi+4096-8], 0C001h
            ;4K PDE
            mov         edi, 0C000h+2048
            mov         eax, dword[bootboot.fb_ptr] ;map framebuffer
            mov         al,81h
            mov         ecx, 255
@@:         stosd
            add         edi, 4
            add         eax, 2*1024*1024
            dec         ecx
            jnz         @b
            mov         dword [0C000h+4096-8], 0D001h

            ;4K PT
            mov         dword[0D000h], 08001h   ;map bootboot
            mov         dword[0D008h], 09001h   ;map configuration
            mov         edi, 0D010h
            mov         eax, dword[core_ptr]    ;map ELF text segment
            inc         eax
            mov         ecx, 509
@@:         stosd
            add         edi, 4
            add         eax, 4096
            dec         ecx
            jnz         @b
            mov         dword[0DFF8h], 014001h  ;map core stack

            ;identity mapping
            ;2M PDPE
            mov         edi, 0E000h
            mov         dword [edi], 0F001h
            mov         dword [edi+8], 010001h
            mov         dword [edi+16], 011001h
            mov         dword [edi+24], 012001h
            ;2M PDE
            mov         edi, 0F000h
            xor         eax, eax
            mov         al, 81h
            mov         ecx, 512*  4;G RAM
@@:         stosd
            add         edi, 4
            add         eax, 2*1024*1024
            dec         ecx
            jnz         @b
            ;first 2M mapped by page
            mov         dword [0F000h], 013001h
            mov         edi, 013000h
            mov         eax, 1
            mov         ecx, 512
@@:         stosd
            add         edi, 4
            add         eax, 4096
            dec         ecx
            jnz         @b

            ;generate new 64 bit gdt
            mov         edi, GDT_table+8
            ;8h core data
            xor         eax, eax        ;supervisor mode (ring 0)
            stosd
            mov         eax, 00809200h
            stosd
            ;10h core code
            xor         eax, eax        ;flat data segment
            stosd
            mov         eax, 00209800h
            stosd
            ;18h mandatory tss
            xor         eax, eax        ;required by vt-x
            stosd
            mov         eax, 00008900h
            stosd
            ;patch gdtr size
            mov         eax, edi
            sub         eax, GDT_table
            mov         word [GDT_value], ax
            ;clear old segment
            xor         eax, eax
            stosd
            stosd

            ;Enter long mode
            mov         al, 0FFh        ;disable PIC
            out         021h, al
            out         0A1h, al
            in          al, 70h         ;disable NMI
            or          al, 80h
            out         70h, al

            mov         eax, 10100000b  ;Set PAE and PGE
            mov         cr4, eax
            mov         eax, 0A000h
            mov         cr3, eax
            mov         ecx, 0C0000080h ;EFER MSR
            rdmsr
            or          eax, 100h       ;enable long mode
            wrmsr

            mov         eax, cr0
            or          eax, 80000001h
            mov         cr0, eax        ;enable paging
            lgdt        [GDT_value]     ;read 80 bit address
            xor         eax, eax
            mov         ax, 8
            mov         ds, ax
            mov         es, ax
            mov         ss, ax
            mov         fs, ax
            mov         gs, ax
            jmp         16:longmode_init
            USE64
longmode_init:
            xor         rsp, rsp
            mov         rax, 'BOOTBOOT'             ; magic
            mov         rbx, 0FFFFFFFFFFE00000h     ; bootboot virtual address
            mov         rcx, 0FFFFFFFFFFE01000h     ; environment virtual address
            mov         rdx, 0FFFFFFFFE0000000h     ; framebuffer virtual address
            ;call _start() at qword[entrypoint]
            push        qword[entrypoint]
            ret
            USE32
            include     "fs.inc"

;*********************************************************************
;*                               Data                                *
;*********************************************************************
            ;global descriptor table
            align       16
GDT_table:  dd          0, 0                ;null descriptor
DATA_PROT   =           $-GDT_table
            dd          0000FFFFh,008F9200h ;flat ds
CODE_BOOT   =           $-GDT_table
            dd          0000FFFFh,00009800h ;16 bit legacy real mode cs
CODE_PROT   =           $-GDT_table
            dd          0000FFFFh,00CF9A00h ;32 bit prot mode ring0 cs
            dd          00000068h,00CF8900h ;32 bit TSS, not used but required
GDT_value:  dw          $-GDT_table
            dd          GDT_table
            dd          0,0
            align       16
entrypoint: dq          0
core_ptr:   dd          0
ebdaptr:    dd          0
hw_stack:   dd          0
lastmsg:    dd          0
lbapacket:              ;lba packet for BIOS
.size:      dw          10h
.count:     dw          8
.addr:      dd          0A000h
.sect0:     dd          0
.sect1:     dd          0
.flataddr:  dd          0,0
reqwidth:   dd          0
reqheight:  dd          0
bootdev:    db          0
vbememsize: dw          0
panic:      db          "-PANIC: ",0
noarch:     db          "Hardware not supported",0
a20err:     db          "Failed to enable A20",0
memerr:     db          "E820 memory map not found",0
noenmem:    db          "Not enough memory",0
noacpi:     db          "ACPI not found",0
nogpt:      db          "GUID Partition Table not found or corrupt",0
nord:       db          "FS0:\BOOTBOOT\INITRD not found",0
noroot:     db          "Root directory not found in initrd",0
nolib:      db          "/lib directory not found in initrd",0
nocore:     db          "Kernel not found in initrd",0
badcore:    db          "Kernel is not an executable ELF64 for x86_64",0
novbe:      db          "VESA VBE error, no framebuffer",0
nogzip:     db          "Compressed initrd not supported yet",0
kernel:     db          "lib/sys/core"
            db          (256-($-kernel)) dup 0
;-----------padding to be multiple of 512----------
            db          (511-($-loader+511) mod 512) dup 0
loader_end:

;-----------BIOS checksum------------
chksum = 0
repeat $-loader
    load b byte from (loader+%-1)
    chksum = (chksum + b) mod 100h
end repeat
store byte (100h-chksum) at (loader.checksum)

;-----------bound check-------------
;fasm will generate an error if the code
;is bigger than it should be
db  07C00h-4096-($-loader) dup ?
