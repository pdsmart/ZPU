
    .file "premain.s"

; Define weak linkage for _premain, so that it can be overridden
    .section ".text","ax"
    .weak _premain
_premain:
    ;    clear BSS data, then call main.
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
    im _break           ; &_break bssptr+4
    storesp 4           ; &_break
    im main             ; &main &break
    poppc               ; &break

; There is a bug in the code below, the incremented variable after increment and store is lost, hence the explanation
; of what is happening during ZPU code execution to establish where in the ZPU logic the bug lays.
PC     SP     TOS      NOS      In.DecIn
000000 007ff8 00000000 00000000 00.00       000:    
000000 007ff8 00000000 00000000 0b.1d       000:    0b              nop
000001 007ff8 0b0b0b88 00000000 0b.1d       001:    0b              nop
000002 007ff8 0b0b0b88 00000000 0b.1d       002:    0b              nop
000003 007ff8 0b0b0b88 00000000 88.11       003:    88              im _premain
000005 007ff4 0000046d 0b0b0b88 04.20       005:    04              poppc
                                       0000046d <_premain>:
00046d 007ff8 0b0b0b88 00000000 a9.11       46d:	b0          	im 48               : NOS -> 007ffc, NOS = TOS, TOS = __bss_start__, 1xPUSH
                                            46e:	c8          	im -56
                                       0000046f <.clearloop>:
00046f 007ff4 0000149c 0b0b0b88 70.17       46f:	70          	loadsp 0            : NOS -> 007ff8, TOS = TOS, NOS = TOS, 1xPUSH
000470 007ff0 0000149c 0000149c a9.11       470:	b1          	im 49               : NOS -> 007ff4, NOS = TOS, TOS = __bss_end__, 1xPUSH
                                            471:	a8          	im 40
000472 007fec 000014c4 0000149c 27.2d       472:	27          	ulessthanorequal    : TOS = 0 (>), NOS <- 007ff4, 1xPOP
000473 007ff0 00000000 0000149c 8b.11       473:	8b          	im 11               : NOS -> 007ff4, NOS = TOS, TOS = .done, 1xPUSH
000474 007fec 0000000b 00000000 38.1c       474:	38          	neqbranch           : TOS <- 007ff4, NOS <- 007ff0, 2xPOP
000475 007ff4 0000149c>0000149c<80.11       475:	80          	im 0                : NOS -> 007ff8, NOS = TOS, TOS = 0, 1xPUSH
                      *0000000*
000476 007ff0 00000000 0000149c 71.17       476:	71          	loadsp 4            : NOS -> 007ff4, TOS = NOS, NOS = TOS, 1xPUSH
000477 007fec 0000149c 00000000 70.17       477:	70          	loadsp 0            : NOS -> 007ff0, TOS = TOS, NOS = TOS, 1xPUSH
000478 007fe8 0000149c 0000149c 84.11       478:	84          	im 4                : NOS -> 007fec, NOS = TOS, TOS = 4, 1xPUSH
000479 007fe4 00000004 0000149c 05.00       479:	05          	add                 : TOS = TOS + NOS, NOS <- 007fec, 1xPOP
00047a 007fe8 000014a0 0000149c 53.2a       47a:	53          	storesp 12          : TOS -> 007ff4, TOS = NOS, 1xPOP
00047b 007fec 0000149c>0000149c<0c.27       47b:	0c          	store               : TOS <- 007fec, NOS <- 007ff0, 2xPOP
                      *00000000*
00047c 007ff4 0000149c>000014a0<88.11       47c:	88          	im 8                : NOS -> 007ff8, NOS = TOS, TOS = .clearloop, 1xPUSH
                      *00000000*
                                            47d:	ef          	im -17
00047e 007ff0 0000046f>0000149c<04.20       47e:	04          	poppc               : PC=TOS, TOS = NOS, NOS <- 007ff8, 2xPOP
                      *000014a0*
00046f 007ff4>0000149c 000014a0<70.17       46f:	70          	loadsp 0            : NOS -> 007ff8, TOS = TOS, NOS = TOS, 1xPUSH
000470 007ff0 0000149c 0000149c a9.11       470:	b1          	im 49               : NOS -> 007ff4, NOS = TOS, TOS = __bss_end__, 1xPUSH
                                            471:	a8          	im 40
000472 007fec 000014c4 0000149c 27.2d       472:	27          	ulessthanorequal    : TOS = 0 (>), NOS <- 007ff4, 1xPOP
000473 007ff0 00000000 0000149c 8b.11       473:	8b          	im 11               : NOS -> 007ff4, NOS = TOS, TOS = .done, 1xPUSH
000474 007fec 0000000b 00000000 38.1c       474:	38          	neqbranch           : TOS <- 007ff4, NOS <- 007ff0, 2xPOP
000475 007ff4 0000149c 0000149c 80.11       475:	80          	im 0                : NOS -> 007ff8, NOS = TOS, TOS = 0, 1xPUSH
000476 007ff0 00000000 0000149c 71.17       476:	71          	loadsp 4            : NOS -> 007ff4, TOS = NOS, NOS = TOS, 1xPUSH
000477 007fec 0000149c 00000000 70.17       477:	70          	loadsp 0            : NOS -> 007ff0, TOS = TOS, NOS = TOS, 1xPUSH
000478 007fe8 0000149c 0000149c 84.11       478:	84          	im 4                : NOS -> 007fec, NOS = TOS, TOS = 4, 1xPUSH
000479 007fe4 00000004 0000149c 05.00       479:	05          	add                 : TOS = TOS + NOS, NOS <- 007fec, 1xPOP
00047a 007fe8 000014a0 0000149c 53.2a       47a:	53          	storesp 12          : TOS -> 007ff4, TOS = NOS, 1xPOP
00047b 007fec 0000149c 0000149c 0c.27       47b:	0c          	store               : TOS <- 007fec, NOS <- 007ff0, 2xPOP
00047c 007ff4 0000149c 000014a0 88.11       47c:	88          	im 8                : NOS -> 007ff8, NOS = TOS, TOS = .clearloop, 1xPUSH
                                            47d:	ef          	im -17 
00047e 007ff0 0000046f 0000149c 04.20       47e:	04          	poppc               : PC=TOS, TOS = NOS, NOS <- 007ff8, 2xPOP
                                       0000047f <.done>:
                                            47f:	88          	im 8
                                            480:	e2          	im -30
                                            481:	51          	storesp 4
                                            482:	9a          	im 26
                                            483:	ab          	im 43
                                            484:	04          	poppc
