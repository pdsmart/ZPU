/* Startup code for ZPU
       Copyright (C) 2005 Free Software Foundation, Inc.

This file is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 2, or (at your option) any
later version.

In addition to the permissions in the GNU General Public License, the
Free Software Foundation gives you unlimited permission to link the
compiled version of this file with other programs, and to distribute
those programs without any restriction coming from the use of this
file.  (The General Public License restrictions do apply in other
respects; for example, they cover modification of the file, and
distribution when not linked into another program.)

This file is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; see the file COPYING.  If not, write to
the Free Software Foundation, 59 Temple Place - Suite 330,
Boston, MA 02111-1307, USA.  */

        .file    "zputaromcrt0.s"
        .include "zpu_macros.s"
        
        
;    .section ".fixed_vectors","ax"
; KLUDGE!!! we remove the executable bit to avoid relaxation 
        .section ".fixed_vectors","a" 

        ; Define the location where the pointer to the interrupt handler is stored.
        .global _inthandler_fptr
        .set _inthandler_fptr, 0x00000400

; DANGER!!!! 
; we need to align these code sections to 32 bytes, which
; means we must not use any assembler instructions that are relaxed
; at linker time
; DANGER!!!! 

/* vectors */
        .balign 32,0
# offset 0x0000 0000
        .globl _start
_start:
        jmp _premain

        .balign 32,0
# offset 0x0000 0020
        .globl _zpu_interrupt_vector
_zpu_interrupt_vector:
        im 8+0        ; save R0
        load
        im 8+4        ; save R1
        load
        im 8+8        ; save R2
        load
        
        fixedim    _inthandler_fptr
        load
        call
                
        im 8+8
        store        ; restore R2
        im 8+4
        store        ; restore R1
        im 8+0
        store        ; restore R0
        poppc

/* instruction emulation code */

# opcode 34
# offset 0x0000 0040
        .balign 32,0
        .global _loadh
_loadh:
        loadsp 4
        ; by not masking out bit 0, we cause a memory access error 
        ; on unaligned access
        im ~0x2
        and
        load

        ; mult 8    
        loadsp 8
        im 3
        and
        fast_neg
        im 2
        add
        im 3
        ashiftleft
        ; shift right addr&3 * 8
        lshiftright
        im 0xffff
        and
        storesp 8
        
        poppc

# opcode 35
# offset 0x0000 0060
        .balign 32,0
        .global _storeh
_storeh:
        loadsp 4
        ; by not masking out bit 0, we cause a memory access error 
        ; on unaligned access
        im ~0x2
        and
        load

        ; mask
        im 0xffff
        loadsp 12
        im 3
        and
        fast_neg
        im 2
        add
        im 3
        ashiftleft
        ashiftleft
        not

        and

        loadsp 12
        im 0xffff

        nop
            
        fixedim _storehtail
        poppc


# opcode 36
# offset 0x0000 0080
        .balign 32,0
_lessthan:
        loadsp 8
        fast_neg
        loadsp 8
        add

        ; DANGER!!!!
        ; 0x80000000 will overflow when negated, so we need to mask
        ; the result above with the compare positive to negative
        ; number case
        loadsp 12
        loadsp 12
        not
        and
        not
        and


        ; handle case where we are comparing a negative number
        ; and positve number. This can underflow. E.g. consider 0x8000000 < 0x1000
        loadsp 12
        not
        loadsp 12
        and
        
        or



        flip
        im 1
        and    

        
        storesp 12
        storesp 4
        poppc
        

# opcode 37
# offset 0x0000 00a0
        .balign 32,0
_lessthanorequal:
        loadsp 8
        loadsp 8
        lessthan
        loadsp 12
        loadsp 12
        eq
        or
        
        storesp 12
        storesp 4
        poppc

        
# opcode 38
# offset 0x0000 00c0
        .balign 32,0
_ulessthan:
        ; fish up arguments 
        loadsp 4
        loadsp 12
        
        /* low: -1 if low bit dif is negative 0 otherwise:  neg (not x&1 and (y&1))
            x&1        y&1        neg (not x&1 and (y&1))
            1        1        0
            1        0         0
            0        1        -1
            0        0        0
        
        */
        loadsp 4 
        not
        loadsp 4
        and
        im 1
        and
/*    neg */
        not
        im 1
        add
        
        
        /* high: upper 31-bit diff is only wrong when diff is 0 and low=-1
            high=x>>1 - y>>1 + low
            
            extremes
            
            0000 - 1111:
            low= neg(not 0 and 1) = 1111 (-1)
            high=000+ neg(111) +low = 000 + 1001 + low = 1000 
            OK
            
            1111 - 0000
            low=neg(not 1 and 0) = 0
            high=111+neg(000) + low = 0111
            OK
             
            
         */
        loadsp 8
        
        flip 
        addsp 0
        flip
        
        loadsp 8
        
        flip    
        addsp 0
        flip

        sub

        ; if they are equal, then the last bit decides...    
        add
        
        /* test if negative: result = flip(diff) & 1 */
        flip
        im 1
        and

        ; destroy a&b which are on stack    
        storesp 4
        storesp 4
        
        storesp 12
        storesp 4
        poppc            

# opcode 39
# offset 0x0000 00e0
        .balign 32,0
_ulessthanorequal:
        loadsp 8
        loadsp 8
        ulessthan
        loadsp 12
        loadsp 12
        eq
        or
        
        storesp 12
        storesp 4
        poppc


# opcode 40
# offset 0x0000 0100
        .balign 32,0
        .globl _swap
_swap:
        breakpoint ; tbd

# opcode 41
# offset 0x0000 0120
        .balign 32,0
_slowmult:
        im _slowmultImpl
        poppc

# opcode 42
# offset 0x0000 0140
        .balign 32,0
_lshiftright:
        loadsp 8
        flip

        loadsp 8
        ashiftleft
        flip
        
        storesp 12
        storesp 4

        poppc
        

# opcode 43
# offset 0x0000 0160
        .balign 32,0
_ashiftleft:
        loadsp 8
        
        loadsp 8
        im 0x1f
        and
        fast_neg
        im _ashiftleftEnd
        add
        poppc
        
        
# opcode 44
# offset 0x0000 0180
        .balign 32,0
_ashiftright:
        loadsp 8
        loadsp 8
        lshiftright
        
        ; handle signed value
        im -1
        loadsp 12
        im 0x1f
        and
        lshiftright
        not    ; now we have an integer on the stack with the signed 
            ; bits in the right position

        ; mask these bits with the signed bit.
        loadsp 16
        not
        flip
        im 1
        and
        im -1
        add
        
        and    
        
        ; stuff in the signed bits...
        or
        
        ; store result into correct stack slot    
        storesp 12
        
        ; move up return value 
        storesp 4
        poppc

# opcode 45
# offset 0x0000 01a0
        .balign 32,0
_call:    ; stack: return_addr call_addr ...
        ; fn
        loadsp 4    ;    call_addr return_addr call_addr ...
        
        ; return address
        loadsp 4    ;   return_addr call_addr return_addr call_addr ...

        ; store return address
        storesp 12    ;   call_addr return_addr return_addr
        
        ; fn to call
        storesp 4    ;   call_addr return_addr
        
;    pushsp    ; flush internal stack
;    popsp
            
        poppc

_storehtail:

        and
        loadsp 12
        im 3
        and
        fast_neg
        im 2
        add
        im 3
        ashiftleft
        nop
        ashiftleft
        
        or
        
        loadsp 8
        im  ~0x3
        and

        store
        
        storesp 4
        storesp 4
        poppc


# opcode 46
# offset 0x0000 01c0
        .balign 32,0
_eq:
        loadsp 8
        fast_neg
        loadsp 8
        add
        
        not 
        loadsp 0
        im 1
        add
        not
        and
        flip
        im 1
        and
        
        storesp 12
        storesp 4
        poppc

# opcode 47
# offset 0x0000 01e0
        .balign 32,0
_neq:
        loadsp 8
        fast_neg
        loadsp 8
        add
        
        not 
        loadsp 0
        im 1
        add
        not
        and
        flip

        not

        im 1
        and
            
        storesp 12
        storesp 4
        poppc
        

# opcode 48
# offset 0x0000 0200
        .balign 32,0
_neg:
        loadsp 4
        not
        im 1
        add
        storesp 8
        
        poppc
        

# opcode 49
# offset 0x0000 0220
        .balign 32,0
_sub:
        loadsp 8
        loadsp 8
        fast_neg
        add
        storesp 12

        storesp 4

        poppc


# opcode 50
# offset 0x0000 0240
        .balign 32,0
_xor:
        loadsp 8
        not
        loadsp 8
        and
        
        loadsp 12
        loadsp 12
        not
        and

        or

        storesp 12
        storesp 4
        poppc

# opcode 51
# offset 0x0000 0260
        .balign 32,0
        .global _loadb
_loadb:
        loadsp 4
        im ~0x3
        and
        load

        loadsp 8
        im 3
        and
        fast_neg
        im 3
        add
        ; x8
        addsp 0
        addsp 0
        addsp 0

        lshiftright

        im 0xff
        and
        storesp 8
        
        poppc


# opcode 52
# offset 0x0000 0280
        .balign 32,0
        .global _storeb
_storeb:
        loadsp 4
        im ~0x3
        and
        load

        ; mask away destination
        im _mask
        loadsp 12
        im 3
        and
        addsp 0
        addsp 0
        add
        load

        and


        im _storebtail
        poppc
        
# opcode 53
# offset 0x0000 02a0
        .balign 32,0
_div:
        cimpl __divsi3
;    breakpoint

# opcode 54
# offset 0x0000 02c0
        .balign 32,0
_mod:
        cimpl __modsi3
;    breakpoint;

# opcode 55
# offset 0x0000 02e0
        .balign 32,0
        .globl _eqbranch
_eqbranch:
        loadsp 8
        
        ; eq

        not 
        loadsp 0
        im 1
        add
        not
        and
        flip
        im 1
        and

        ; mask
        im -1
        add
        loadsp 0
        storesp 16

        ; no branch address
        loadsp 4
        
        and

        ; fetch boolean & neg mask
        loadsp 12
        not
        
        ; calc address & mask for branch
        loadsp 8
        loadsp 16
        add
        ; subtract 1 to find PC of branch instruction
        im -1
        add
        
        and

        or    
        
        storesp 4
        storesp 4
        storesp 4
        poppc    


# opcode 56
# offset 0x0000 0300
        .balign 32,0
        .globl _neqbranch
_neqbranch:
        loadsp 8
        
        ; neq

        not 
        loadsp 0
        im 1
        add
        not
        and
        flip
        
        not
        
        im 1
        and

        ; mask
        im -1
        add
        loadsp 0
        storesp 16

        ; no branch address
        loadsp 4
        
        and

        ; fetch boolean & neg mask
        loadsp 12
        not
        
        ; calc address & mask for branch
        loadsp 8
        loadsp 16
        add
        ; find address of branch instruction
        im -1
        add
        
        and

        or    
        
        storesp 4
        storesp 4
        storesp 4
        poppc    

# opcode 57
# offset 0x0000 0320
        .balign 32,0
        .globl _poppcrel
_poppcrel:
        add
        ; address of poppcrel
        im -1
        add
        poppc
            
# opcode 58
# offset 0x0000 0340
        .balign 32,0
        .globl _config
_config:
#    im 1
#    nop
#    im _hardware
#    store
#    storesp 4
        poppc

# opcode 59
# offset 0x0000 0360
        .balign 32,0
_pushpc:
        loadsp 4
        im 1
        add 
        storesp 8
        poppc
        
# opcode 60
# offset 0x0000 0380
        .balign 32,0
_syscall_emulate:
        poppc
        .byte 0
        
# opcode 61
# offset 0x0000 03a0
        .balign 32,0
_pushspadd:
        pushsp
        im 4
        add
        loadsp 8
        addsp 0
        addsp 0
        add
        storesp 8
        
        poppc

# opcode 62
# offset 0x0000 03c0
        .balign 32,0
_halfmult:
        breakpoint
        
# opcode 63
# offset 0x0000 03e0
        .balign 32,0
_callpcrel:
        loadsp 4
        loadsp 4
        add
        im -1
        add
        loadsp 4
        
        storesp 12    ; return address
        storesp 4 
        pushsp        ; this will flush the internal stack.
        popsp
        poppc

        ; ZPUTA Jump table begins after the first 0x400 reserved bytes.
        .org 0x400,255

        ; By definition, the first 32 bytes when ZPUTA is an IOCP App are used as startup code, so when ZPUTA is the primary boot firmware, the first 32 bytes
        ; are used as follows.

        ; Interrupt handler address.
        .balign 4,0
        .long _default_inthandler

        .balign 32, 255

        ;--------------------------------
        ; ZPUTA API
        ;--------------------------------
        ;
        ; ZPUTA API calls for external sub-programs. Allows code snippets (apps) to use the logic built-in to ZPUTA, thus keeping
        ; the app code base small.
        ; This is a fixed size jump table which invokes the actual api code, per function, in the main .text
        ; section, allowing for optimizations.

        ; Break handler.
        jmp     _break

        ; putc and xprint calls
        ;
        jmp     __putchar
        jmp     _xputc
        jmp     _xfputc
        jmp     _xputs
        jmp     _xgets
        jmp     _xfgets
        jmp     _xfputs
        jmp     _xatoi
        jmp     _uxatoi
        jmp     _xprintf
        jmp     _xsprintf
        jmp     _xfprintf
        ;
        ; getc calls
        ;
        jmp     _getserial
        jmp     _getserial_nonblocking
        ;
        ; Util calls.
        ;
       ;jmp     _crc32_init
       ;jmp     _crc32_addword
        jmp     _get_dword
        jmp     _rtcSet
        jmp     _rtcGet
        ;
        ; FatFS System Calls.
        ;
        jmp     _f_open
        jmp     _f_close
        jmp     _f_read
        jmp     _f_write
        jmp     _f_lseek
        jmp     _f_truncate
        jmp     _f_sync
        jmp     _f_opendir
        jmp     _f_closedir
        jmp     _f_readdir
       ;jmp     _f_findfirst
       ;jmp     _f_findnext
        jmp     _f_mkdir
        jmp     _f_unlink
        jmp     _f_rename
        jmp     _f_stat
        jmp     _f_chmod
        jmp     _f_utime
        jmp     _f_chdir
        jmp     _f_chdrive
        jmp     _f_getcwd
        jmp     _f_getfree
        jmp     _f_getlabel
        jmp     _f_setlabel
       ;jmp     _f_forward
        jmp     _f_expand
        jmp     _f_mount
        jmp     _f_mkfs
       ;jmp     _f_fdisk
       ;jmp     _f_setcp
       ;jmp     _f_putc
       ;jmp     _f_puts
       ;jmp     _f_printf
       ;jmp     _f_gets
        ;
        ; Low level disk calls.
        ;
        jmp     _disk_read
        jmp     _disk_write
        jmp     _disk_ioctl
        ;
        ; Miscellaneous Calls.
        ;
        jmp     _getStrParam
        jmp     _getUintParam
        jmp     _set_serial_output
       ;jmp     _printBytesPerSec
        jmp     _printFSCode

        ;--------------------------------
        ; End of ZPUTA API
        ;--------------------------------

        ;--------------------------------
        ; Main application startup.
        ;--------------------------------

        .org 0x600,255
        .section ".text","ax"

        .balign 4,0
_default_inthandler:
        poppc

        .global _break;
_break:
        breakpoint
        im    _break
        poppc ; infinite loop

        ;
        ; putc and xprint calls
        ;
        defapi  _putchar
        defapi  xputc
        defapi  xfputc
        defapi  xputs
        defapi  xgets
        defapi  xfgets
        defapi  xfputs
        defapi  xatoi
        defapi  uxatoi
        defapi  xprintf
        defapi  xsprintf
        defapi  xfprintf
        ;
        ; getc calls
        ;
        defapi  getserial
        defapi  getserial_nonblocking
        ;
        ; Util calls.
        ;
       ;defapi  crc32_init
       ;defapi  crc32_addword
        defapi  get_dword
        defapi  rtcSet
        defapi  rtcGet
        ;
        ; FatFS System Calls.
        ;
        defapi  f_open
        defapi  f_close
        defapi  f_read
        defapi  f_write
        defapi  f_lseek
        defapi  f_truncate
        defapi  f_sync
        defapi  f_opendir
        defapi  f_closedir
        defapi  f_readdir
       ;defapi  f_findfirst
       ;defapi  f_findnext
        defapi  f_mkdir
        defapi  f_unlink
        defapi  f_rename
        defapi  f_stat
        defapi  f_chmod
        defapi  f_utime
        defapi  f_chdir
        defapi  f_chdrive
        defapi  f_getcwd
        defapi  f_getfree
        defapi  f_getlabel
        defapi  f_setlabel
       ;defapi  f_forward
        defapi  f_expand
        defapi  f_mount
        defapi  f_mkfs
       ;defapi  f_fdisk
       ;defapi  f_setcp
       ;defapi  f_putc
       ;defapi  f_puts
       ;defapi  f_printf
       ;defapi  f_gets
        ;
        ; Low level disk calls.
        ;
        defapi  disk_read
        defapi  disk_write
        defapi  disk_ioctl
        ;
        ; Miscellaneous Calls.
        ;
        defapi  getStrParam
        defapi  getUintParam
        defapi  set_serial_output
       ;defapi  printBytesPerSec
        defapi  printFSCode

;       .global _boot
;_boot:
;       im -1
;       popsp ;    Reset stack to 0x....ffff
;       im 0
;       poppc ; and jump to 0

; NB! this is not an EMULATE instruction. It is a varargs fn.
        .global _syscall    
_syscall:
        syscall
        poppc

        .balign 4,0
_ashiftleftBegin:
        .rept 0x1f
        addsp 0
        .endr
_ashiftleftEnd:
        storesp 12
        storesp 4
        poppc
        
        .balign 4,0
_storebtail:
        loadsp 12
        im 0xff
        and
        loadsp 12
        im 3
        and

        fast_neg
        im 3
        add
        ; x8
        addsp 0
        addsp 0
        addsp 0

        ashiftleft
         
        or
        
        loadsp 8
        im  ~0x3
        and

        store
        
        storesp 4
        storesp 4
        poppc
        
        
_slowmultImpl:
        
        loadsp 8 ; A
        loadsp 8 ; B
        im 0 ; C

.LmoreMult:
        mult1bit
        
        ; cutoff
        loadsp 8
        .byte (.LmoreMult-.Lbranch)&0x7f+0x80
.Lbranch:
        neqbranch

        storesp 4
        storesp 4
        storesp 12
        storesp 4
        poppc

; Define weak linkage for _premain, so that it can be overridden
        .weak _premain
_premain:
        ;    clear BSS data, then call main.

        im __bss_start__    ; bssptr
.clearloop:
        loadsp 0            ; bssptr bssptr 
        im __bss_end__        ; __bss_end__  bssptr bssptr
        ulessthanorequal    ; (bssptr<=__bss_end__?) bssptr
        impcrel .done        ; &.done (bssptr<=__bss_end__?) bssptr
        neqbranch            ; bssptr
        im 0                ; 0 bssptr
        loadsp 4            ; bssptr 0 bssptr
        loadsp 0            ; bssptr bssptr 0 bssptr
        im 4                ; 4 bssptr bssptr 0 bssptr
        add                    ; bssptr+4 bssptr 0 bssptr
        storesp 12            ; bssptr 0 bssptr+4
        store                ; (write 0->bssptr)  bssptr+4
        im .clearloop        ; &.clearloop bssptr+4
        poppc                ; bssptr+4
.done:
        im _break            ; &_break bssptr+4
        storesp 4            ; &_break
        im main                ; &main &break
        poppc                ; &break

        
        .section ".rodata"
        .balign 4,0
_mask:
        .long 0x00ffffff
        .long 0xff00ffff
        .long 0xffff00ff
        .long 0xffffff00

        .section ".bss"
        .balign 4,0
        .globl _memreg
_memreg:
        .long 0
        .long 0
        .long 0
        .long 0    
