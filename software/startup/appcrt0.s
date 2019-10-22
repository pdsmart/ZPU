;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Name:            appcrt0.h
;; Created:         July 2019
;; Author(s):       Philip Smart
;; Description:     ZPUTA application startup code.
;;                  This is the assembler startup file of any C compiled APPlication for the ZPUTA
;;                  program. It specifies the entry points into ZPUTA for standard functions
;;                  and also the stack manipulation to handle parameters and return codes for the
;;                  C APPlication (ie. ZPUTA Calls APP with parameters and APP returns a result code).
;;
;; Credits:         
;; Copyright:       (c) 2019 Philip Smart <philip.smart@net2net.org>
;;
;; History:         July 2019   - Initial script written.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; This source file is free software: you can redistribute it and#or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This source file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http:;;www.gnu.org;licenses;>.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    .file    "appcrt0.s"
    .include "zpu_macros.s"

    .section ".fixed_vectors","a"

    ; Define the location where the pointer to the interrupt handler is stored.
    .global _inthandler_fptr
    .set _inthandler_fptr, 0x00000400

    .balign 16,0
    .global _start
_start:
    im 0                ; Store return address into stack.
    pushspadd
    popsp

    fixedim _premain    ; Jump to initialisation routine.
    poppc

    ; Fixed entry point for ZPUTA API calls. Return codes are stored in ZPUTA namespace so a transfer must take
    ; place into the app namespace. This is implemented by the API jumping to this fixed entry point and the
    ; return code copied.
    .balign 16,0
_callret:
    im _memreg+16       ; Get address of memreg 1 in zputa
    load
    load                ; Get value at _memreg in zputa
    im _memreg          ; 
    store               ; Place return code into memreg 1 in this app.
    poppc               ; Return to original caller.
    

    ;-----------------------------------------------
    ; ZPUTA API Function Entry Points
    ;-----------------------------------------------
    ;
    ; Entry points in the parent program, ZPUTA, where the relevvant named functions can be accessed. The
    ; entry point in this table is used as the address for the specified function in the APPlication such that
    ; a call to a library function in the APPlication is actually using code in ZPUTA at runtime thus minimising
    ; code in the APPlication.
    ;
    .equ funcNext,  0x06;
    .equ funcAddr,  ZPUTA_BASEADDR+0x20;
    defapifunc      break funcAddr
    ;
    ; putc and xprint calls.
    ;
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      putchar funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      xputc funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      xfputc funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      xputs funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      xgets funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      xfgets funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      xfputs funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      xatoi funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      uxatoi funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      xprintf funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      xsprintf funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      xfprintf funcAddr
    ;
    ; getc calls
    ;
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      getserial funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      getserial_nonblocking funcAddr
    ;
    ; Util calls
    ;
  ;  .equ funcAddr,  funcAddr+funcNext;
  ;  defapifunc      crc32_init funcAddr
  ;  .equ funcAddr,  funcAddr+funcNext;
  ;  defapifunc      crc32_addword funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      get_dword funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      rtcSet funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      rtcGet funcAddr
    ;
    ;FatFS System Calls
    ;
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_open funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_close funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_read funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_write funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_lseek funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_truncate funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_sync funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_opendir funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_closedir funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_readdir funcAddr
   ;.equ funcAddr,  funcAddr+funcNext;
   ;defapifunc      f_findfirst funcAddr
   ;.equ funcAddr,  funcAddr+funcNext;
   ;defapifunc      f_findnext funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_mkdir funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_unlink funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_rename funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_stat funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_chmod funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_utime funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_chdir funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_chdrive funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_getcwd funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_getfree funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_getlabel funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_setlabel funcAddr
   ;.equ funcAddr,  funcAddr+funcNext;
   ;defapifunc      f_forward funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_expand funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_mount funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      f_mkfs funcAddr
   ;.equ funcAddr,  funcAddr+funcNext;
   ;defapifunc      f_fdisk funcAddr
   ;.equ funcAddr,  funcAddr+funcNext;
   ;defapifunc      f_setcp funcAddr
   ;.equ funcAddr,  funcAddr+funcNext;
   ;defapifunc      f_putc funcAddr
   ;.equ funcAddr,  funcAddr+funcNext;
   ;defapifunc      f_puts funcAddr
   ;.equ funcAddr,  funcAddr+funcNext;
   ;defapifunc      f_printf funcAddr
   ;.equ funcAddr,  funcAddr+funcNext;
   ;defapifunc      f_gets funcAddr
   ;
   ; Low level disk calls.
   ;
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      disk_read funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      disk_write funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      disk_ioctl funcAddr
   ;
   ; Miscellaneous calls.
   ;
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      getStrParam funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      getUintParam funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      set_serial_output funcAddr
;    .equ funcAddr,  funcAddr+funcNext;
;    defapifunc      printBytesPerSec funcAddr
    .equ funcAddr,  funcAddr+funcNext;
    defapifunc      printFSCode funcAddr



    ;--------------------------------------
    ; Start of the main application program
    ;--------------------------------------

    ; Define weak linkage for _premain, so that it can be overridden
    .section ".text","ax"
    .weak _premain

    ; Clear BSS data, then start app() - the main entry point into the
    ; APPlication.
_premain:
    im __bss_start__    ; bssptr
.clearloop:
    loadsp 0            ; bssptr bssptr 
    im __bss_end__      ; __bss_end__  bssptr bssptr
    ulessthanorequal    ; (bssptr<=__bss_end__?) bssptr
    impcrel .done       ; &.done (bssptr<=__bss_end__?) bssptr
    neqbranch           ; bssptr
    im 0                ; 0 bssptr
    loadsp 4            ; bssptr 0 bssptr
    loadsp 0            ; bssptr bssptr 0 bssptr
    im 4                ; 4 bssptr bssptr 0 bssptr
    add                 ; bssptr+4 bssptr 0 bssptr
    storesp 12          ; bssptr 0 bssptr+4
    store               ; (write 0->bssptr)  bssptr+4
    im .clearloop       ; &.clearloop bssptr+4
    poppc               ; bssptr+4
.done:
    im .appret          ; &.appret bssptr+4
    storesp 4           ; &.appret

    im 8                ; Param5 = address of cfgSoC structure in ZPUTA memory space to be available in this application.
    pushspadd
    load
    im cfgSoC           ; Setup the location of the pointer to cfgSoC variable in the app
    store               ; and place value into the pointer.

    im 7                ; Param4 = address of G(lobal) structure in ZPUTA memory space to be available in this application.
    pushspadd
    load
    im G                ; Setup the location of the pointer to G(lobal) variable in the app
    store               ; and place value into the pointer.

    im 6                ; Param3 = memreg 1 address in zputa, location where return code is expected to be placed.
    pushspadd
    load
    im _memreg+16       ; Set the store location to memreg 4 in the app
    store               ; and place memreg 1 in zputa into memreg 4 of this app.

    im 5                ; &Param2 &.appret
    pushspadd
    load
    nop
    im 5                ; &Param1 &Param2 &.appret
    pushspadd
    load
    im app              ; &app &Param1 &Param2 &.appret
    call                ; &.appret

    im _memreg          ; Get return code from memreg 1 in this app.
    load
    im _memreg+16       ; Get address of memreg 1 in zputa
    load
    store               ; Place return code into memreg 1 in zputa.

.appret:
    im 5                ; Adjust stack so that return address is in TOS
    pushspadd
    popsp
    poppc               ; Return to zputa (caller).

    ; NB! this is not an EMULATE instruction. It is a varargs fn.
    .globl _syscall    
_syscall:
    syscall
    poppc

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
_memreg:                ; C required memory registers stored at begininning of bss segment.
        .long 0
        .long 0
        .long 0
        .long 0
        .long 0         ; Non standard memory register used to hold the address of memreg in ZPUTA so this application can query it.

    ; End of startup code.
