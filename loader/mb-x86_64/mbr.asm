;*
;* loader/mb-x86_64/mbr.asm
;*
;* Copyright 2016 Public Domain BOOTBOOT bztsrc@github
;*
;* This file is part of the BOOTBOOT Protocol package.
;* @brief 1nd stage loader, compatible with BIOS boot specification
;*

;*********************************************************************
;*                             Macros                                *
;*********************************************************************

;LBA packet fields
virtual at lba_packet
lbapacket.size: dw      ?
lbapacket.count:dw      ?
lbapacket.addr0:dw      ?
lbapacket.addr1:dw      ?
lbapacket.sect0:dw      ?
lbapacket.sect1:dw      ?
lbapacket.sect2:dw      ?
lbapacket.sect3:dw      ?
end virtual

;memory locations
ldr.header      equ     800h        ;position of 2nd stage loader
ldr.executor    equ     804h        ;ptr to init code

;Writes a message on screen.
macro print msg
{
if ~ msg eq si
            push        si
            mov         si, msg
end if
            call        printfunc
if ~ msg eq si
            pop         si
end if
}

;*********************************************************************
;*                             code                                  *
;*********************************************************************

;-----------------ENTRY POINT called by BIOS--------------------
            ORG         0600h
            USE16

bootboot_record:
            cli
            jmp         short .skipid
.system:    db          "OS/Z",0
.skipid:    ;relocate our code to offset 600h
            xor         ax, ax
            mov         ss, ax
            mov         sp, 600h
            push        ax
            pop         es
            push        cs
            pop         ds
            ;find our position in memory.
            call        .getaddr
.getaddr:   pop         si
            sub         si, .getaddr-bootboot_record
            cld
            mov         di, sp
            ;clear data area 500h-600h
            sub         di, 100h
            mov         cx, 80h
            repnz       stosw
            ;and copy ourselves to 600h
            mov         cx, 100h
            repnz       movsw
            jmp         0:.start

.start:     ;save boot drive code
            mov         byte [drive], dl
            ;initialize lba packet
            mov         byte [lbapacket.size], 16
            mov         byte [lbapacket.count], 58
            mov         byte [lbapacket.addr0+1], 08h   ;to address 800h
            push        dx
            print       .system
            pop         dx
            ;check for lba presistance - floppy not supported any more
            ;we use pendrive as removable media for a long time
            cmp         dl, byte 80h
            jl          .nolba
.notfloppy: mov         ah, byte 41h
            mov         bx, word 55AAh
            int         13h
            jc          .nolba
            cmp         bx, word 0AA55h
            jne         .nolba
            test        cl, byte 1
            jnz         .lbaok
.nolba:     mov         si, lbanotf
            jmp         diefunc
.lbaok:     ;try to load stage2 - it's a continous area on disk
            ;started at given sector with maximum size of 7400h bytes
            mov         si, stage2_addr
            mov         di, lbapacket.sect0
            push        di
            movsw
            movsw
            movsw
            movsw
            call        loadsectorfunc

            ;do we have a 2nd stage loader?
.chk:       cmp         word [ldr.header], bx
            jne         .nostage2
            cmp         byte [ldr.header+3], 0E9h
            jne         .nostage2
xchg bx,bx
            ;invoke stage2 real mode code
            print       okay
            mov         ax, [ldr.executor]
            add         ax, ldr.executor+3
            jmp         ax

.nostage2:  mov         si, stage2notf
            ;fall into the diefunc code

;*********************************************************************
;*                          functions                                *
;*********************************************************************
;writes the reason, waits for a key and reboots.
diefunc:
            print       panic
            call        printfunc
            mov         si, found
            call        printfunc
            sti
            xor         ax, ax
            int         16h
            mov         al, 0FEh
            out         64h, al
            jmp         far 0FFFFh:0    ;invoke BIOS POST routine

;loads an LBA sector
loadsectorfunc:
            push        bx
            push        si
            mov         ah, byte 42h
            mov         dl, byte [drive]
            mov         si, lba_packet
            int         13h
            pop         si
            pop         bx
            ret

;ds:si zero terminated string to write
printfunc:
            lodsb
            or          al, al
            jz          .end
            mov         ah, byte 0Eh
            mov         bx, word 11
            int         10h
            jmp         printfunc
.end:       ret

;*********************************************************************
;*                          data area                                *
;*********************************************************************

panic:      db          "-PANIC: ",0
lbanotf:    db          "LBA support",0
stage2notf: db          "FS0:\BOOTBOOT\LOADER",0
found:      db          " not found",10,13,0
okay:       db          " booting...",10,13,0
drive:      db          0
lba_packet: db          01B0h-($-$$) dup 0

;right before the partition table some data
stage2_addr:dd          0FFFFFFFFh,0    ;1B0h 2nd stage loader address
                                        ;this should be set by mkfs

diskid:     dd          0               ;1B8h WinNT expects it here
            dw          0

;1BEh first partition entry

            ;padding and magic
            db          01FEh-($-$$) dup 0
            db          55h,0AAh
bootboot_record_end:
