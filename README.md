Please consult my [GitHub](https://pdsmart.github.io) website for more upto date information.
<br>
<br>

The ZPU is a 32bit Stack based microprocessor and was designed by Øyvind Harboe from [Zylin AS](https://opensource.zylin.com/) and original documentation can be found on the [Zylin/OpenCore website or Wikipedia](https://en.wikipedia.org/wiki/ZPU_\(microprocessor\)). It is a microprocessor intended for FPGA embedded applications with minimal logic element and BRAM usage with the sacrifice of speed of execution. 

Zylin produced two designs which it made open source, namely the Small and Medium ZPU versions. Additional designs were produced by external developers such as the Flex and ZPUino variations, each offering enhancements to the original design such as Wishbone interface, performance etc.

This document describes another design which I like to deem as the ZPU Evo(lution) model whose focus is on *performance*, *connectivity* and *instruction expansion*. This came about as I needed a CPU for an emulator of a vintage computer i am writing which would act as the IO processor to provide Menu, Peripheral and SD services.

An example of the *performance* of the ZPU Evo can be seen using CoreMark which returns a value of 19.1 @ 100MHz on Altera fabric using BRAM and for Dhrystone 11.2DMIPS. Comparisons can be made with the original ZPU designs in the gallery below paying attention to the CoreMark score which seems to be the defacto standard now. *Connectivity* can be seen via implementation of both System and Wishbone buses, allowing for connection of many opensource IP devices. *Instruction expansion* can be seen by the inclusion of a close coupled L1 cache where multiple instruction bytes are sourced and made available to the CPU which in turn can be used for optimization (ie. upto 5 IM instructions executed in 1 cycle) or for extended multi-byte instructions (ie. implementation of a LoaD Increment Repeat instruction). There is room for a lot more improvements such as stack cache, SDRAM to L2 burst mode, parallel instruction execution (ie. and + neqbranch) which are on my list.


# The CPU

The ZPU Evo follows on from the ZPU Medium and Flex and areas of the code are similar, for example the instruction decoding. The design differs though due to caching and implementation of a Memory Transaction Processor where all Memory/IO operations (except for direct Instruction reads if dual-port instruction bus is enabled) are routed. The original CPU's all handled their memory requirements in-situ or part of the state machine whereas the Evo submits a request to the MXP whenever a memory operation is required.

The following sections indicate some of the features and changes to original ZPU designs.

### Bus structure

The ZPU has a linear address space with all memory and IO devices directly addressable within this space. Existing ZPU designs either provide a system bus or a wishbone bus whereas the Evo provides both. The ZPU Evo creates up to two distinct regions within the address space depending on configuration, to provide a *system bus* and a *wishbone bus*.

All models have the system bus instantiated which starts at cpu address 0 and expands up-to the limit imposed by the configurable maximum address bit (ie. 0x000000 - 0xFFFFFF for 24bit). A dedicated memory mapped IO region is set aside at the top of the address space (albeit it could quite easily be in any location) ie. 0xFF0000 - 0xFFFFFF.

If configured, a wishbone bus can be instantiated and this extends the maximum address bit by 1 (ie. 0x1000000 - 0x1FFFFFF for 24bit example). This in effect creates 2 identical regions, the lower being controlled via the system bus, the upper via the wishbone bus. As per the system bus, the upper area of the wishbone address space is reserved for IO devices.

A third bus can be configured, which is for instruction reads only. This bus typically shadows the system bus in memory region but is deemed to be connected to fast access memory for reading of instructions without the need for L2 Cache. This would typically be the 2nd port of a dual-port BRAM block with the 1st port connected to the system bus. 

### L1 Cache

In order to gain performance but more especially for instruction optimisations and extended instructions, an L1 cache is implemented using registers. Using registers consumes fabric space so should be very small but it allows random access in a single cycle which is needed for example if compacting a 32bit IM load (which can be 5 instructions) into a single cycle. Also for extended instructions, the first byte indicates an extended instruction and the following 1-5 bytes defines the instruction which is then executed in a single cycle.

### L2 Cache

Internal BRAM (on-board Block RAM within the FPGA) doesn't need an L2 Cache as it's access time is 1-2 cycles. As BRAM is a limited resource it is assumed external RAM or SDRAM will be used which is much slower and this needs to be cached to increase throughput. The L2 Cache is used for this purpose, to read ahead a block of external RAM and feed the L1 Cache as needed. On analysis, the C programs generated by GCC are typically loops and calls within a local area (unless using large libraries), so implementing a simple direct mapping cache between external RAM and BRAM (used for the L2 Cache) indexed relative to the Program Counter is sufficient to keep the CPU from stalling most of the time.

### Instruction Set

A feature of the ZPU is it's use of a minimal fixed set of hardware implemented instructions and a soft set of additional instructions which are implemented in pseudo micro-code (ie. the fixed set of instructions). This is achieved by 32byte vectors in the region 0x0000 - 0x0400 and each soft instruction branches to the vector if it is not implemented in hardware. The benefit is reduced FPGA resources but the penalty is performance.

The ZPU Evo implements all instructions in hardware but this can be adjusted in the configuration to use soft instructions if required in order to conserve FPGA resources. This allows for a balance of resources versus performance. Ultimately though, if resources are tight then the use of the Small/Flex ZPU models may be a better choice.

In addition to the original instructions, a mechanism exists to extend the instruction set using multi-byte instructions of the format:-

***Extend Instruction,<new insn[7:2]+ParamSize[1:0]>,[byte],[byte],[byte],[byte]***

Where ParamSize = 00 - No parameter bytes
                                    01 - 8 bit parameter
                                    10 - 16 bit parameter
                                    11 - 32 bit parameter

Some extended instructions are under development (ie. LDIR) an exact opcode value and extended instruction set has not yet been fully defined. The GNU AS assembler will be updated with these instructions so they can be invoked within a C program and eventually if they have benefit to C will be migrated into the GCC compiler (ie. ADD32/DIV32/MULT32/LDIR/LDDR as from what I have seen, these will have a big impact on CoreMark/Dhrystone tests).


### Implemented Instruction Set

| Name             | Opcode    |           | Description                                                                                                                                                                                                                                                            |
|------------------|-----------|-----------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| BREAKPOINT       | 0         | 00000000  | The debugger sets a memory location to this value to set a breakpoint. Once a JTAG-like debugger interface is added, it will be convenient to be able to distinguish between a breakpoint and an illegal(possibly emulated) instruction.                               |
| IM               | 1xxx xxxx | 1xxx xxxx | Pushes 7 bit sign extended integer and sets the a «instruction decode interrupt mask» flag(IDIM).<br>If the IDIM flag is already set, this instruction shifts the value on the stack left by 7 bits and stores the 7 bit immediate value into the lower 7 bits.<br>Unless an instruction is listed as treating the IDIM flag specially, it should be assumed to clear the IDIM flag.<br>To push a 14 bit integer onto the stack, use two consecutive IM instructions.<br> If multiple immediate integers are to be pushed onto the stack, they must be interleaved with another instruction, typically NOP.  |
| STORESP          | 010x xxxx | 010x xxxx | Pop value off stack and store it in the SP+xxxxx*4 memory location, where xxxxx is a positive integer.                                                                                                                                                                 |
| LOADSP           | 011x xxxx | 011x xxxx | Push value of memory location SP+xxxxx*4, where xxxxx is a positive integer, onto stack.                                                                                                                                                                               |
| ADDSP            | 0001 xxxx | 0001 xxxx | Add value of memory location SP+xxxx*4 to value on top of stack.                                                                                                                                                                                                       |
| EMULATE          | 001x xxxx | 010x xxxx | Push PC to stack and set PC to 0x0+xxxxx*32. This is used to emulate opcodes. See zpupgk.vhd for list of emulate opcode values used. zpu_core.vhd contains reference implementations of these instructions rather than letting the ZPU execute the EMULATE instruction.<br>One way to improve performance of the ZPU is to implement some of the EMULATE instructions.|
| PUSHPC           | emulated  | emulated  | Pushes program counter onto the stack.                                                                                                                                                                                                                                 |
| POPPC            | 0000 0100 | 0000 0100 | Pops address off stack and sets PC                                                                                                                                                                                                                                     |
| LOAD             | 0000 1000 | 0000 1000 | Pops address stored on stack and loads the value of that address onto stack.<br>Bit 0 and 1 of address are always treated as 0(i.e. ignored) by the HDL implementations and C code is guaranteed by the programming model never to use 32 bit LOAD on non-32 bit aligned addresses(i.e. if a program does this, then it has a bug).|
| STORE            | 0000 1100 | 0000 1100 | Pops address, then value from stack and stores the value into the memory location of the address.<br>Bit 0 and 1 of address are always treated as 0                                                                                                                    |
| PUSHSP           | 0000 0010 | 0000 0010 | Pushes stack pointer.                                                                                                                                                                                                                                                  |
| POPSP            | 0000 1101 | 0000 1101 | Pops value off top of stack and sets SP to that value. Used to allocate/deallocate space on stack for variables or when changing threads.                                                                                                                              |
| ADD              | 0000 0101 | 0000 0101 | Pops two values on stack adds them and pushes the result                                                                                                                                                                                                               |
| AND              | 0000 0110 | 0000 0110 | Pops two values off the stack and does a bitwise-and & pushes the result onto the stack                                                                                                                                                                                |
| OR               | 0000 0111 | 0000 0111 | Pops two integers, does a bitwise or and pushes result                                                                                                                                                                                                                 |
| NOT              | 0000 1001 | 0000 1001 | Bitwise inverse of value on stack                                                                                                                                                                                                                                      |
| FLIP             | 0000 1010 | 0000 1010 | Reverses the bit order of the value on the stack, i.e. abc->cba, 100->001, 110->011, etc.<br>The raison d'etre for this instruction is mainly to emulate other instructions.                                                                                           |
| NOP              | 0000 1011 | 0000 1011 | No operation, clears IDIM flag as side effect, i.e. used between two consecutive IM instructions to push two values onto the stack.                                                                                                                                    |
| PUSHSPADD        | 61        | 00111101  | a=sp;<br>b=popIntStack()*4;<br>pushIntStack(a+b);<br>                                                                                                                                                                                                                  |
| POPPCREL         | 57        | 00111001  | setPc(popIntStack()+getPc());                                                                                                                                                                                                                                          |
| SUB              | 49        | 00110001  | int a=popIntStack();<br>int b=popIntStack();<br>pushIntStack(b-a);                                                                                                                                                                                                     |
| XOR              | 50        |           | pushIntStack(popIntStack() ^ popIntStack());                                                                                                                                                                                                                           |
| LOADB            | 51        |           | 8 bit load instruction. Really only here for compatibility with C programming model. Also it has a big impact on DMIPS test.<br>pushIntStack(cpuReadByte(popIntStack())&0xff);                                                                                         |
| STOREB           | 52        |           | 8 bit store instruction. Really only here for compatibility with C programming model. Also it has a big impact on DMIPS test. <br>addr = popIntStack();<br>val = popIntStack();<br>cpuWriteByte(addr, val);                                                            |
| LOADH            | 34        |           | 16 bit load instruction. Really only here for compatibility with C programming model.<br>pushIntStack(cpuReadWord(popIntStack()));                                                                                                                                     |
| STOREH           | 35        |           | 16 bit store instruction. Really only here for compatibility with C programming model.<br>addr = popIntStack();<br>val = popIntStack();<br>cpuWriteWord(addr, val);<br>                                                                                                |
| LESSTHAN         | 36        |           | Signed comparison<br>a = popIntStack();<br>b = popIntStack();<br>pushIntStack((a < b) ? 1 : 0);                                                                                                                                                                        |
| LESSTHANOREQUAL  | 37        |           | Signed comparison<br>a = popIntStack();<br>b = popIntStack();<br>pushIntStack((a <= b) ? 1 : 0);                                                                                                                                                                       |
| ULESSTHAN        | 38        |           | Unsigned comparison<br>long a;  //long is here 64 bit signed integer<br>long b;<br>a = ((long) popIntStack()) & INTMASK; // INTMASK is unsigned 0x00000000ffffffff<br>b = ((long) popIntStack()) & INTMASK;<br>pushIntStack((a < b) ? 1 : 0);                          |
| ULESSTHANOREQUAL | 39        |           | Unsigned comparison<br>long a;  //long is here 64 bit signed integer<br>long b;<br>a = ((long) popIntStack()) & INTMASK; // INTMASK is unsigned 0x00000000ffffffff<br>b = ((long) popIntStack()) & INTMASK;<br>pushIntStack((a <= b) ? 1 : 0);                         |
| EQBRANCH         | 55        |           | int compare;<br>int target;<br>target = popIntStack() + pc;<br>compare = popIntStack();<br>if (compare == 0)<br>{<br>setPc(target);<br>} else<br>{<br>setPc(pc + 1);<br>}                                                                                              |
| NEQBRANCH        | 56        |           | int compare;<br>int target;<br>target = popIntStack() + pc;<br>compare = popIntStack();<br>if (compare != 0)<br>{<br>setPc(target);<br>} else<br>{<br>setPc(pc + 1);<br>}                                                                                              |
| MULT             | 41        |           | Signed 32 bit multiply<br>pushIntStack(popIntStack() * popIntStack());                                                                                                                                                                                                 |
| DIV              | 53        |           | Signed 32 bit integer divide.<br>a = popIntStack();<br>b = popIntStack();<br>if (b == 0)<br>{<br>// undefined<br>} pushIntStack(a / b);                                                                                                                                |
| MOD              | 54        |           | Signed 32 bit integer modulo.<br>a = popIntStack();<br>b = popIntStack();<br>if (b == 0)<br>{<br>// undefined<br>}<br>pushIntStack(a % b);                                                                                                                             |
| LSHIFTRIGHT      | 42        |           | unsigned shift right.<br>long shift;<br>long valX;<br>int t;<br>shift = ((long) popIntStack()) & INTMASK;<br>valX = ((long) popIntStack()) & INTMASK;<br>t = (int) (valX >> (shift & 0x3f));<br>pushIntStack(t);                                                       |
| ASHIFTLEFT       | 43        |           | arithmetic(signed) shift left.<br>long shift;<br>long valX;<br>shift = ((long) popIntStack()) & INTMASK;<br>valX = ((long) popIntStack()) & INTMASK;<br>int t = (int) (valX << (shift & 0x3f));<br>pushIntStack(t);                                                    |
| ASHIFTRIGHT      | 43        |           | arithmetic(signed) shift left.<br>long shift;<br>int valX;<br>shift = ((long) popIntStack()) & INTMASK;<br>valX = popIntStack();<br>int t = valX >> (shift & 0x3f);<br>pushIntStack(t);                                                                                |
| CALL             | 45        |           | call procedure.<br>int address = pop();<br>push(pc + 1);<br>setPc(address);                                                                                                                                                                                            |
| CALLPCREL        | 63        |           | call procedure pc relative<br>int address = pop();<br>push(pc + 1);<br>setPc(address+pc);                                                                                                                                                                              |
| EQ               | 46        |           | pushIntStack((popIntStack() == popIntStack()) ? 1 : 0);                                                                                                                                                                                                                |
| NEQ              | 47        |           | pushIntStack((popIntStack() != popIntStack()) ? 1 : 0);                                                                                                                                                                                                                |
| NEG              | 48        |           | pushIntStack(-popIntStack());                                                                                                                                                                                                                                          |

<br>

### Implemented Instructions Comparison Table

![alt text](https://github.com/pdsmart/ZPU/blob/master/docs/ImplInstructions.png)

### Hardware Variable Byte Write

In the original ZPU designs there was scope but not the implementation to allow the ZPU to perform byte/half-word/full-word writes. Either the CPU always had to perform 32bit Word aligned operations or it performed the operation in micro-code.

In the Evo, hardware was implemented (build time selectable) to allow Byte and Half-Word writes and also hardware Read-Update-Write operations. If the hardware Byte/Half-Word logic is not enabled then it falls back to the 32bit Word Read-Update-Write logic. Both methods have performance benefits, the latter taking 3 cycles longer.

### Hardware Debug Serializer

In order to debug the CPU or just provide low level internal operating information, a cached UART debug module is implemented. Currently this is only for output but has the intention to be tied into the IOCP for in-situ debugging when Simulation/Signal-Tap is not available.

Embedded within the CPU RTL are statements which issue snapshot information to the serialiser, if  enabled in the configuration along with the information level. This is then serialized and output to a connected terminal. A snapshot of the output information can be seen below (with manual comments):

|                                                              |
| ------------------------------------------------------------ |
| 000477 01ffec 00001ae4 00000000 70.17 04770484 046c047c 08f0046c 0b848015 17700500 05000500 05001188 11ef2004  <br/><br/><u>Break Point - Illegal instruction</u><br/>000478 01ffe8 00001ae4 00001ae4 00.05 04780484 046c0478 08f0046c 0b888094 05000500 05000500 118811ef 20041188  <br/><br/><u>L1 Cache Dump</u><br/>000478 (480)-> 11 e2 2a 51 11 a0 11 8f <-(483) (004)->11 ed 20 04 05 00 05 00 05 00 05 00 05 00 05 00 20 (46c)->04 11 b5 11 e4 17 70 <-(46f)<br/>      (004)-> 11 ed 20 04 05 00 05 00 05 00 05 00 05 00 05 00 20 (46c)->04 11 b5 11 e4 17 70 11 b6 11 c4 2d 27 11 8b <-(473)<br/>       05 00 05 00 05 00 05 00 (46c)->20 04 11 b5 11 e4 17 70 11 b6 11 c4 2d 27 11 8b 1c 38 11 80 17 71 17 70 -<(477)<br/>(46c)->20 04 11 b5 11 e4 17 70 11 b6 11 c4 2d 27 11 8b 1c 38 11 80 17 71 17 70 -<(477) 05 00 05 00 05 00 05 00 <br/>(470)->11 b6 11 c4 2d 27 11 8b 1c 38 11 80 17 71 17 70 <-(477) -> 05 00 05 00 05 00 05 00 (47c)->11 88 11 ef 20 04 11 88 <-(47f)<br/>(474)->1c 38 11 80 17 71 17 70 05 00 05 00 05 00 05 00 11 88 11 ef 20 04 11 88 11 e2 2a 51 11 a0 11 8f <br/>       05 00 05 00 05 00 05 00 11 88 11 ef 20 04 11 88 11 e2 2a 51 11 a0 11 8f 11 ed 20 04 05 00 05 00 <br/>       11 88 11 ef 20 04 11 88 11 e2 2a 51 11 a0 11 8f 11 ed 20 04 05 00 05 00 05 00 05 00 05 00 05 00 <br/><u>L2 Cache Dump</u><br/>000000 88 08 8c 08 ed 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 <br/>000020 88 08 8c 08 90 08 0b 0b 0b 88 80 08 2d 90 0c 8c 0c 88 0c 04 00 00 00 00 00 00 00 00 00 00 00 00 <br/>000040 71 fd 06 08 72 83 06 09 81 05 82 05 83 2b 2a 83 ff ff 06 52 04 00 00 00 00 00 00 00 00 00 00 00 |

All critical information such as current instruction being executed (or not if stalled), Signals/Flags, L1/L2 Cache contents and Memory contents can be output.



# System On a Chip

In order to provide a working framework in which the ZPU Evo could be used, a System On a Chip wrapper was created which allows for the instantiation of various devices (ie. UART/SD card). 

As part of the development, the ZPU Small/Medium/Flex models were incorporated into the framework allowing the choice of CPU when fabric space is at a premium or comparing CPU's, albeit features such as Wishbone are not available on the original ZPU models. I didn't include the ZPUino as this design already has a very good eco system or the ZY2000.

The SoC currently implements (in the build tree):

| Component                 | Selectable (ie not hardwired)                                |
| ------------------------- | ------------------------------------------------------------ |
| CPU                       | Choice of ZPU Small, Medium, Flex, Evo or Evo Minimal.       |
| Wishbone Bus              | Yes, 32 bit bus.                                             |
| (SB) BRAM                 | Yes, implement a configurable block of BRAM as the boot loader and stack. |
| Instruction Bus BRAM      | Yes, enable a separate bus (or Dual-Port) to the boot code implemented in BRAM. This is generally a dual-port BRAM shared with the Sysbus BRAM but can be independent. |
| (SB) RAM                  | Implement a block of BRAM as RAM, seperate from the BRAM used for the boot loader/stack. |
| (WB) SDRAM                | Yes, implement an SDRAM controller over the Wishbone bus.    |
| (WB) RAM                  | Implement a block of BRAM as RAM over the Wishbone bus.      |
| (WB) I2C                  | Yes, implements an I2C Controller over the Wishbone bus.     |
| (SB) Timer 0              | No, implements a hardware 12bit Second, 18bit milliSec and 24bit uSec down counter with interrupt, a 32bit milliSec up counter with interrupt and a YMD HMS Real Time Clock. The down counters are ideal for scheduling. |
| (SB) Timer 1              | Yes, a selectable number of pre-scaled 32bit down counters.  |
| (SB) UART 0               | No, a cached UART used for monitor output and command input/program load. |
| (SB) UART 1               | No, a cached UART used for software (C program)/hardware (ZPU debug serializer) output. |
| (SB) Interrupt Controller | Yes, a prioritized configurable (# of inputs) interrupt controller. |
| (SB) PS2                  | Yes, a PS2 Keyboard and Mouse controller.                    |
| (SB) SPI                  | Yes, a configurable number of Serial Peripheral Interface controllers. |
| (SB) SD                   | Yes, a configurable number of hardware based SPI SD controllers. |
| (SB) SOCCFG               | Yes, a set of registers to indicate configuration of the ZPU and SoC to the controlling program. |

Within the SoC configuration, items such as starting Stack Address, Reset Vector, IO Start/End (SB) and (WB) can be specified. Given the wishbone bus, it is very easy to add further opencore IP devices, for the system bus some work may be needed as the opencore IP devices use differing signals.

# Software

The software provided includes:

1. A bootloader, I/O Control Program (IOCP). This is more than a bootloader, in its basic form it can bootstrap an application from an SD card or it can include command line monitor tools and a serial upload function.
2. An application, ZPUTA (ZPU Test Application). This is a test suite and can be organised as a single application or split into a Disk Operating System where all functionality is stored on the SD card. ZPUTA can be bootstrapped by IOCP or standalone as the only program in the ROM/BRAM.
3. A disk operating system, zOS (ZPU Operating System). A version of ZPUTA but aimed at production code where all functionality resides as disk applications.
4. Library functions in C to aid in building applications, including 3rd party libs ie. FatFS from El. Chan

### IOCP

The I/O Control Program (IOCP) is basically a bootloader, it can operate standalone or as the first stage in booting an application. At the time of writing the following functionality and memory maps have been defined in the build.sh and within the parameterisation of the IOCP/ZPUTA/RTL but any other is possible by adjusting the parameters.

 - Tiny - IOCP is the smallest size possible to boot from SD Card. It is useful for a SoC configuration where there is limited BRAM and the applications loaded from the SD card would potentially run in external RAM.
 - Minimum - As per tiny but adds: print IOCP version, interrupt handler, boot message and SD error messages. 
 - Medium - As per small but adds: command line processor to add commands below, timer on auto boot so it can be disabled by pressing a key

    | Command | Description                                |
    | ------- | ------------------------------------------ |
    | 1       | Boot Application in Application area BRAM  |
    | 4       | Dump out BRAM (boot) memory                |
    | 5       | Dump out Stack memory                      |
    | 6       | Dump out application RAM                   |
    | C       | Clear Application area of BRAM             |
    | c       | Clear Application RAM                      |
    | d       | List the SD Cards directory                |
    | R       | Reset the system and boot as per power on  |
    | h       | Print out help on enabled commands         |
    | i       | Prints version information                 |

 - Full - As medium but adds additional commands below.

    | Command | Description                                |
    | ------- | ------------------------------------------ |
    | 2       | Upload to BRAM application area, in binary format, from serial port |
    | 3       | Upload to RAM, in binary format, from serial port |
    | i       | Print detailed SoC configuration           |

### ZPUTA

ZPUTA started life as a basic test application to verify ZPU Evo and SoC operations. As it evolved and different FPGA's were included in the ZPU Evo scope, it became clear that it had to be more advanced due to limited resources. 

ZPUTA has two primary methods of execution, a) as an application booted by IOCP, b) standalone booted as the ZPU Evo startup firmware. The mode is chosen in the configuration and functionality is identical.

In order to cater for limited FPGA BRAM resources, all functionality of ZPUTA can be enabled/disabled within the loaded image. If an SD Card is present then some/all functionality can be shifted from the loaded image into applets (1 applet per function, ie. memory clear) and stored on the SD card - this mode is like DOS where typing a command retrieves the applet from SD card and executes it.

The functionality currently provided by ZPUTA can be summarised as follows.

| Category                      | Command  | Parameters                          | Description                                     |
| --------                      | -------  | ----------                          | ----------------------------------------------- |
| Disk IO Commands              | ddump    | \[<pd#> \<sect>]                    | Dump a sector                                   |
|                               | dinit    | \<pd#> \[\<card type>]              | Initialize disk                                 |
|                               | dstat    | \<pd#>                              | Show disk status                                |
|                               | dioctl   | \<pd#>                              | ioctl(CTRL_SYNC)                                | 
| Disk Buffer Commands          | bdump    | \<ofs>                              | Dump buffer                                     |
|                               | bedit    | \<ofs> \[\<data>] ...               | Edit buffer                                     |
|                               | bread    | \<pd#> \<sect> \[\<num>]            | Read into buffer                                |
|                               | bwrite   | \<pd#> \<sect> \[\<num>]            | Write buffer to disk                            |
|                               | bfill    | \<val>                              | Fill buffer                                     |
|                               | blen     | \<len>                              | Set read/write length for fread/fwrite command  |
| Filesystem Commands           | finit    | \<ld#> \[\<mount>]                  | Force init the volume                           |
|                               | fopen    | \<mode> \<file>                     | Open a file                                     |
|                               | fclose   |                                     | Close the open file                             |
|                               | fseek    | \<ofs>                              | Move fp in normal seek                          |
|                               | fread    | \<len>                              | Read part of file into buffer                   |
|                               | finspect | \<len>                              | Read part of file and examine                   |
|                               | fwrite   | \<len> \<val>                       | Write part of buffer into file                  |
|                               | ftrunc   |                                     | Truncate the file at current fp                 |
|                               | falloc   | \<fsz> \<opt>                       | Allocate ctg blks to file                       |
|                               | fattr    | \<atrr> \<mask> \<name>             | Change object attribute                         |
|                               | ftime    | <y> <m> <d> <h> <M> <s> <fn>        | Change object timestamp                         |
|                               | frename  | \<org name> \<new name>             | Rename an object                                |
|                               | fdel     | \<obj name>                         | Delete an object                                |
|                               | fmkdir   | \<dir name>                         | Create a directory                              |
|                               | fstat    | \[\<path>]                          | Show volume status                              |
|                               | fdir     | \[\<path>]                          | Show a directory                                |
|                               | fcat     | \<name>                             | Output file contents                            |
|                               | fcp      | \<src file> \<dst file>             | Copy a file                                     |
|                               | fconcat  | \<src fn1> \<src fn2> \<dst fn>     | Concatenate 2 files                             |
|                               | fxtract  | \<src> \<dst> \<start pos> \<len>   | Extract a portion of file                       |
|                               | fload    | \<name> \[\<addr>]                  | Load a file into memory                         |
|                               | fexec    | \<name> \<ldAddr> \<xAddr> \<mode>  | Load and execute file                           |
|                               | fsave    | \<name> \<addr> \<len>              | Save memory range to a file                     |
|                               | fdump    | \<name> \[\<width>]                 | Dump a file contents as hex                     |
|                               | fcd      | \<path>                             | Change current directory                        |
|                               | fdrive   | \<path>                             | Change current drive                            |
|                               | fshowdir |                                     | Show current directory                          |
|                               | flabel   | \<label>                            | Set volume label                                |
|                               | fmkfs    | \<ld#> \<type> \<au>                | Create FAT volume                               |
| Memory Commands               | mclear   | \<start> \<end> \[\<word>]          | Clear memory                                    |
|                               | mcopy    | \<start> \<end> \<dst addr>         | Copy memory                                     |
|                               | mdiff    | \<start> \<end> \<cmp addr>         | Compare memory                                  |
|                               | mdump    | \[\<start> \[\<end>] \[\<size>]]    | Dump memory                                     |
|                               | mtest    | \[\<start> \[\<end>] \[iter]        | Test memory                                     |
|                               | meb      | \<addr> \<byte> \[...]              | Edit memory (Bytes)                             |
|                               | meh      | \<addr> \<h-word> \[...]            | Edit memory (H-Word)                            |
|                               | mew      | \<addr> \<word> \[...]              | Edit memory (Word)                              |
| Hardware Commands             | hid      |                                     | Disable Interrupts                              |
|                               | hie      |                                     | Enable Interrupts                               |
|                               | hr       |                                     | Display Register Information                    |
|                               | ht       |                                     | Test uS Timer                                   |
|                               | hfd      |                                     | Disable UART FIFO                               |
|                               | hfe      |                                     | Enable UART FIFO                                |
| Performance Testing Commands  | dhry     |                                     | Dhrystone Test v2.1                             |
|                               | coremark |                                     | CoreMark Test v1.0                              |
| Program Execution Commands    | call     | \<addr>                             | Call function @ \<addr>                         |
|                               | jmp      | \<addr>                             | Execute code @ \<addr>                          |
| Miscellaneous Commands        | restart  |                                     | Restart application                             |
|                               | reset    |                                     | Reset system                                    |
|                               | help     | \[\<cmd %>\|\<group %>]             | Show this screen                                |
|                               | info     |                                     | Config info                                     |
|                               | time     | \[\<y> \<m> \<d> \<h> \<M> \<s>]    | Set/Show current time                           |
|                               | test     |                                     | Test Screen                                     |

All of the above commands can be disabled, built-in or created as an SD based applet.

### zOS

zOS is under development but is basically an optimised version of ZPUTA stripping out unnecessary logic and targetting it as the primary operating system for ZPU Evo use in my FPGA applications such as the SharpMZ emulator.

zOS will be uploaded to the repository when I feel it is in a good alpha state.


### Memory Maps

The currently defined memory maps for IOCP/ZPUTA/Applications are as follows:-


![IOCP Memory Map](https://github.com/pdsmart/ZPU/blob/master/docs/IOCPMemoryMap.png)


For ZPUTA, it can either be configured to be the boot application (ie. no IOCP) or it can be configured as an App booted by IOCP. Depending upon how ZPUTA is built. it can have applets (portions of its functionality created as dedicated executables on the SD card) or standalone with all functionality inbuilt. The former is used when there is limited memory or a set of loadable programs is desired.

![ZPUTA Memory Map](https://github.com/pdsmart/ZPU/blob/master/docs/ZPUTAMemoryMap.png)

<br>

# Build

This section shows how to make a basic build and assumes the target development board is the [QMTECH Cyclone V board](https://github.com/ChinaQMTECH/QM_CYCLONE_V). There are many configuration options but these will be covered seperately.

### Software build

Jenkins can be used to automate the build but for simple get up and go compilation use the build.sh and hierarchical Makefile system following the basic instructions here.

1. Download and install the [ZPU GCC ToolChain](https://github.com/zylin/zpugcc). Install into /opt or similar common area.
2. Setup the environment variable path.
```shell
    export PATH=$PATH:/opt/zpu/bin
```
3. Clone the [ZPU Evo](https://github.com/pdsmart/zpu) repository
4. Edit the \<zpu evo dir>/software/zputa/zputa.h file and select which functions you want building into the zputa core image (by default, all functions are built as applets but these will be ignored if they are built into the zputa core image). You select a function by setting the BUILTIN_<utility>  to '1', set to '0' if you dont want it built in.
5. Decide which memory map you want and wether ZPUTA will be an application or bootloader (for your own applications, it is they same kind of choice), see build.sh in the table below for options. Once decided, issue the build command.
```shell
    cd <zpu evo dir>/software
    # For this build we have chosen a Tiny IOCP Bootloader, building ZPUTA as an
    # application with a Tiny IOCP bootloader, the ZPUTA Base Address is 0x1000
    # and the address where Applets are loaded and executed is at 0xC000 
    ./build.sh -I 3 -O zputa -o 2 -B 0x1000 -A 0xC000
    # The build command automatically creates the VHDL BRAM images with the IOCP
    # Bootloader installed, thus you will need to build the ZPU Evo SOF bit stream
    # and upload it to the FPGA in order for the new Bootloader to be active.
```
6. Place an SD Card into your system and format it for exFAT format then copy the files onto it.
```shell
    cd build/SD
    cp -r * <abs path to SD card, ie. /media/psmart/ZPU>
    # eject the SD card and install it into the SD card reader on your FPGA dev board. 
```

### RTL Bit Stream build

1. Install [Intel Quartus Prime 17.1](http://fpgasoftware.intel.com/17.1/?edition=lite) or later.
2. Open Quartus Prime and load project (File -> Open Project) and select \<zpu evo dir>/build/QMV_zpu.qpf
3. Compile (Processing -> Start)

&nbsp;&nbsp;&nbsp;&nbsp;*alternatively*:-
1. Install [Intel Quartus Prime 17.1](http://fpgasoftware.intel.com/17.1/?edition=lite) or later.
2. Use the Makefile build system by issuing the commands.
```shell
    cd <zpu evo dir>/build
    make QMV_EVO
```

### Configure for ZPU Small Build

The ZPU Small CPU can be built by changing the configuration as follows:

````
cd <repository>
````
````
Edit: zpu_soc_pkg.vhd

1. Change to the desired CPU as follows:
    constant ZPU_SMALL                :     integer    := 1;                                                -- Use the SMALL CPU.
    constant ZPU_MEDIUM               :     integer    := 0;                                                -- Use the MEDIUM CPU.
    constant ZPU_FLEX                 :     integer    := 0;                                                -- Use the FLEX CPU.
    constant ZPU_EVO                  :     integer    := 0;                                                -- Use the EVOLUTION CPU.
    constant ZPU_EVO_MINIMAL          :     integer    := 0;                                                -- Use the Minimalist EVOLUTION CPU.

2. Disable WishBone devices as the ZPU Small doesnt support the wishbone interface:
    constant SOC_IMPL_WB_I2C          :     boolean    := false;                                            -- Implement I2C over wishbone interface.
    constant SOC_IMPL_WB_SDRAM        :     boolean    := false;                                            -- Implement SDRAM over wishbone interface.

3. Disable any other devices you dont need, such as PS2 by setting the flag to false.

4. If your using a frequency other than 100MHz as your main clock, enter it in the table
   below against your board. If you are using a different board, add a constant with
   suitable name and use this in your TopLevel (ie. as per E115_zpu_Toplevel.vhd).
   NB. If using your own board it is still imperative that you setup a PLL correctly to
       generate the desired frequency, this constant is used purely for timing based
       calculations such as UART baud rate:

    -- Frequencies for the various boards.
    --
    constant SYSCLK_E115_FREQ         :     integer    := 100000000;                                        -- E115 FPGA Board
    constant SYSCLK_QMV_FREQ          :     integer    := 100000000;                                        -- QMTECH Cyclone V FPGA Board
    constant SYSCLK_DE0_FREQ          :     integer    := 100000000;                                        -- DE0-Nano FPGA Board
    constant SYSCLK_DE10_FREQ         :     integer    := 100000000;                                        -- DE10-Nano FPGA Board
    constant SYSCLK_CYC1000_FREQ      :     integer    := 100000000;                                        -- Trenz CYC1000 FPGA Board
````

````
Edit: cpu/zpu_pkg.vhd

1. Disable wishbone interface as follows:
    constant EVO_USE_WB_BUS           :     boolean          := false;                               -- Implement the wishbone interface in addition to the standard direct interface. NB: Change WB_ACTIVE to 1 above if enabling.

2. If you want to enable debug output on UART 1 then set the DEBUG flag to true along with
   the correct baud rate and sufficiently large FIFO Cache:
    constant DEBUG_CPU                :     boolean          := true;                                -- Enable CPU debugging output.
    constant DEBUG_MAX_TX_FIFO_BITS   :     integer          := 12;                                  -- Size of UART TX Fifo for debug output.
    constant DEBUG_MAX_FIFO_BITS      :     integer          := 3;                                   -- Size of debug output data records fifo.
    constant DEBUG_TX_BAUD_RATE       :     integer          := 115200; --230400;                    -- Baud rate for the debug transmitter
````

Using Quartus Prime following the 'iRTL Bit Stream build' above, build the RTL in the usual manner with this new configuration. You cannot use the Makefile build as it will entail Makefile changes so just use the Quartus Prime GUI at this time.<br><br>The software is the same and unless you have less memory, no changes need to be made to the software build.<br>

### Configure for ZPU Medium Build

The ZPU Medium CPU can be built by changing the configuration as follows:

````
cd <repository>
````
````
Edit: zpu_soc_pkg.vhd

1. Change to the desired CPU as follows:
    constant ZPU_SMALL                :     integer    := 0;                                                -- Use the SMALL CPU.
    constant ZPU_MEDIUM               :     integer    := 1;                                                -- Use the MEDIUM CPU.
    constant ZPU_FLEX                 :     integer    := 0;                                                -- Use the FLEX CPU.
    constant ZPU_EVO                  :     integer    := 0;                                                -- Use the EVOLUTION CPU.
    constant ZPU_EVO_MINIMAL          :     integer    := 0;                                                -- Use the Minimalist EVOLUTION CPU.

2. Disable WishBone devices as the ZPU Medium doesnt support the wishbone interface:
    constant SOC_IMPL_WB_I2C          :     boolean    := false;                                            -- Implement I2C over wishbone interface.
    constant SOC_IMPL_WB_SDRAM        :     boolean    := false;                                            -- Implement SDRAM over wishbone interface.

3. Disable any other devices you dont need, such as PS2 by setting the flag to false.

4. If your using a frequency other than 100MHz as your main clock, enter it in the table
   below against your board. If you are using a different board, add a constant with
   suitable name and use this in your TopLevel (ie. as per E115_zpu_Toplevel.vhd).
   NB. If using your own board it is still imperative that you setup a PLL correctly to
       generate the desired frequency, this constant is used purely for timing based
       calculations such as UART baud rate:

    -- Frequencies for the various boards.
    --
    constant SYSCLK_E115_FREQ         :     integer    := 100000000;                                        -- E115 FPGA Board
    constant SYSCLK_QMV_FREQ          :     integer    := 100000000;                                        -- QMTECH Cyclone V FPGA Board
    constant SYSCLK_DE0_FREQ          :     integer    := 100000000;                                        -- DE0-Nano FPGA Board
    constant SYSCLK_DE10_FREQ         :     integer    := 100000000;                                        -- DE10-Nano FPGA Board
    constant SYSCLK_CYC1000_FREQ      :     integer    := 100000000;                                        -- Trenz CYC1000 FPGA Board
````

````
Edit: cpu/zpu_pkg.vhd

1. Disable wishbone interface as follows:
    constant EVO_USE_WB_BUS           :     boolean          := false;                               -- Implement the wishbone interface in addition to the standard direct interface. NB: Change WB_ACTIVE to 1 above if enabling.

2. If you want to enable debug output on UART 1 then set the DEBUG flag to true along
   with the correct baud rate and sufficiently large FIFO Cache:
    constant DEBUG_CPU                :     boolean          := true;                                -- Enable CPU debugging output.
    constant DEBUG_MAX_TX_FIFO_BITS   :     integer          := 12;                                  -- Size of UART TX Fifo for debug output.
    constant DEBUG_MAX_FIFO_BITS      :     integer          := 3;                                   -- Size of debug output data records fifo.
    constant DEBUG_TX_BAUD_RATE       :     integer          := 115200; --230400;                    -- Baud rate for the debug transmitter
````

Using Quartus Prime following the 'RTL Bit Stream build' above, build the RTL in the usual manner with this new configuration. You cannot use the Makefile build as it will entail Makefile changes so just use the Quartus Prime GUI at this time.<br><br>The software is the same and unless you have less memory, no changes need to be made to the software build.<br>

### Configure for ZPU Flex Build

The ZPU Flex CPU can be built by changing the configuration as follows:

````
cd <repository>
````
````
Edit: zpu_soc_pkg.vhd

1. Change to the desired CPU as follows:
    constant ZPU_SMALL                :     integer    := 0;                                                -- Use the SMALL CPU.
    constant ZPU_MEDIUM               :     integer    := 0;                                                -- Use the MEDIUM CPU.
    constant ZPU_FLEX                 :     integer    := 1;                                                -- Use the FLEX CPU.
    constant ZPU_EVO                  :     integer    := 0;                                                -- Use the EVOLUTION CPU.
    constant ZPU_EVO_MINIMAL          :     integer    := 0;                                                -- Use the Minimalist EVOLUTION CPU.

2. Disable WishBone devices as the ZPU Flex doesnt support the wishbone interface:
    constant SOC_IMPL_WB_I2C          :     boolean    := false;                                            -- Implement I2C over wishbone interface.
    constant SOC_IMPL_WB_SDRAM        :     boolean    := false;                                            -- Implement SDRAM over wishbone interface.

3. Disable any other devices you dont need, such as PS2 by setting the flag to false.

4. If your using a frequency other than 100MHz as your main clock, enter it in the table
   below against your board. If you are using a different board, add a constant with
   suitable name and use this in your TopLevel (ie. as per E115_zpu_Toplevel.vhd).
   NB. If using your own board it is still imperative that you setup a PLL correctly to
       generate the desired frequency, this constant is used purely for timing based
       calculations such as UART baud rate:

    -- Frequencies for the various boards.
    --
    constant SYSCLK_E115_FREQ         :     integer    := 100000000;                                        -- E115 FPGA Board
    constant SYSCLK_QMV_FREQ          :     integer    := 100000000;                                        -- QMTECH Cyclone V FPGA Board
    constant SYSCLK_DE0_FREQ          :     integer    := 100000000;                                        -- DE0-Nano FPGA Board
    constant SYSCLK_DE10_FREQ         :     integer    := 100000000;                                        -- DE10-Nano FPGA Board
    constant SYSCLK_CYC1000_FREQ      :     integer    := 100000000;                                        -- Trenz CYC1000 FPGA Board
````

````
Edit: cpu/zpu_pkg.vhd

1. Disable wishbone interface as follows:
    constant EVO_USE_WB_BUS           :     boolean          := false;                               -- Implement the wishbone interface in addition to the standard direct interface. NB: Change WB_ACTIVE to 1 above if enabling.

2. If you want to enable debug output on UART 1 then set the DEBUG flag to true along with
   the correct baud rate and sufficiently large FIFO Cache:
    constant DEBUG_CPU                :     boolean          := true;                                -- Enable CPU debugging output.
    constant DEBUG_MAX_TX_FIFO_BITS   :     integer          := 12;                                  -- Size of UART TX Fifo for debug output.
    constant DEBUG_MAX_FIFO_BITS      :     integer          := 3;                                   -- Size of debug output data records fifo.
    constant DEBUG_TX_BAUD_RATE       :     integer          := 115200; --230400;                    -- Baud rate for the debug transmitter
````

Using Quartus Prime following the 'RTL Bit Stream build' above, build the RTL in the usual manner with this new configuration. You cannot use the Makefile build as it will entail Makefile changes so just use the Quartus Prime GUI at this time.<br><br>The software is the same and unless you have less memory, no changes need to be made to the software build.<br>

### Configure for ZPU Evo Build

The ZPU Evo has 2 pre-defined versions, the same CPU using different settings. These are the EVO and 'EVO MINIMAL'. The latter implements most of its instructions in micro-code like the ZPU Small.
Assuming we are building the EVO without the WishBone interface, change the configuration as follows:

````
cd <repository>
````
````
Edit: zpu_soc_pkg.vhd

1. Change to the desired CPU as follows:
    constant ZPU_SMALL                :     integer    := 0;                                                -- Use the SMALL CPU.
    constant ZPU_MEDIUM               :     integer    := 0;                                                -- Use the MEDIUM CPU.
    constant ZPU_FLEX                 :     integer    := 0;                                                -- Use the FLEX CPU.
    constant ZPU_EVO                  :     integer    := 1;                                                -- Use the EVOLUTION CPU.
    constant ZPU_EVO_MINIMAL          :     integer    := 0;                                                -- Use the Minimalist EVOLUTION CPU.

2. Disable WishBone devices as we arent using the wishbone interface:
    constant SOC_IMPL_WB_I2C          :     boolean    := false;                                            -- Implement I2C over wishbone interface.
    constant SOC_IMPL_WB_SDRAM        :     boolean    := false;                                            -- Implement SDRAM over wishbone interface.

3. Disable any other devices you dont need, such as PS2 by setting the flag to false.

4. If your using a frequency other than 100MHz as your main clock, enter it in the table
   below against your board. If you are using a different board, add a constant with
   suitable name and use this in your TopLevel (ie. as per E115_zpu_Toplevel.vhd).
   NB. If using your own board it is still imperative that you setup a PLL correctly to
       generate the desired frequency, this constant is used purely for timing based
       calculations such as UART baud rate:

    -- Frequencies for the various boards.
    --
    constant SYSCLK_E115_FREQ         :     integer    := 100000000;                                        -- E115 FPGA Board
    constant SYSCLK_QMV_FREQ          :     integer    := 100000000;                                        -- QMTECH Cyclone V FPGA Board
    constant SYSCLK_DE0_FREQ          :     integer    := 100000000;                                        -- DE0-Nano FPGA Board
    constant SYSCLK_DE10_FREQ         :     integer    := 100000000;                                        -- DE10-Nano FPGA Board
    constant SYSCLK_CYC1000_FREQ      :     integer    := 100000000;                                        -- Trenz CYC1000 FPGA Board
````

````
Edit: cpu/zpu_pkg.vhd

1. Disable wishbone interface as follows:
    constant EVO_USE_WB_BUS           :     boolean          := false;                               -- Implement the wishbone interface in addition to the standard direct interface. NB: Change WB_ACTIVE to 1 above if enabling.

2. If you want to enable debug output on UART 1 then set the DEBUG flag to true along with
   the correct baud rate and sufficiently large FIFO Cache:
    constant DEBUG_CPU                :     boolean          := true;                                -- Enable CPU debugging output.
    constant DEBUG_MAX_TX_FIFO_BITS   :     integer          := 12;                                  -- Size of UART TX Fifo for debug output.
    constant DEBUG_MAX_FIFO_BITS      :     integer          := 3;                                   -- Size of debug output data records fifo.
    constant DEBUG_TX_BAUD_RATE       :     integer          := 115200; --230400;                    -- Baud rate for the debug transmitter
````

Using Quartus Prime following the 'RTL Bit Stream build' above, build the RTL in the usual manner with this new configuration. You cannot use the Makefile build as it will entail Makefile changes so just use the Quartus Prime GUI at this time.<br><br>The software is the same and unless you have less memory, no changes need to be made to the software build.<br>

### Notes on setting up a new development board 

If you are using your own FPGA board (ie. not one in the list I've tested and created Quartus configuration files for), please ensure you create these necessary files:
````
build/<name of your board>.qpf
build/<name of your board>.qsf
build/<name of your board>_Toplevel.vhd
````

It would be best if you copied an existing configuration and tailored it, ie. if your board uses the Cyclone IV then copy the E115_zpu* files and change as necessary. ie:
````
cp build/E115_zpu.qpf build/NEW_zpu.qpf
cp build/E115_zpu.qsf build/NEW_zpu.qsf
cp build/E115_zpu_Toplevel.vhd build/NEW_zpu_Toplevel.vhd
````

Assuming you copied an existing definition as per above, in the build/NEW_zpu.qpf file, change the PROJECT name according to your board name, ie:
````
PROJECT_REVISION = "NEW_zpu"
````

In the build/NEW_zpu.qsf file, change the pin assignments to those available on your board, ie.


````
#============================================================
# UART
#============================================================
set_location_assignment PIN_A7 -to UART_RX_0
set_location_assignment PIN_B7 -to UART_TX_0
set_location_assignment PIN_C6 -to UART_RX_1
set_location_assignment PIN_D7 -to UART_TX_1
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to UART_TX_0
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to UART_RX_0
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to UART_TX_1
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to UART_RX_1
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to UART_TX_0
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to UART_TX_1

#============================================================
# SD CARD
#============================================================
set_location_assignment PIN_C8 -to SDCARD_MISO[0]
set_location_assignment PIN_C7 -to SDCARD_MOSI[0]
set_location_assignment PIN_B8 -to SDCARD_CLK[0]
set_location_assignment PIN_A8 -to SDCARD_CS[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDCARD_MISO[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDCARD_MOSI[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDCARD_CLK[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDCARD_CS[0]
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to SDCARD_MOSI[0]
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to SDCARD_CLK[0]
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to SDCARD_CS[0]

#============================================================
# CLOCK
#============================================================
set_location_assignment PIN_AB11 -to CLOCK_25
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CLOCK_25
#set_location_assignment PIN_AB11 -to clk_25M
````

In the above snippet, if you have PIN_Y7 available for UART 0 RX, then change as follows:
````
#set_location_assignment PIN_A7 -to UART_RX_0
set_location_assignment PIN_Y7 -to UART_RX_0
````

Do this for the UART, SD CARD and CLOCK as a minimum.

You will also have to check and change the PLL assignment, either using one of the predefined configs or creating your own.
````
set_global_assignment -name QIP_FILE Clock_25to100.qip
````

ie. If you have a 12MHz primary clock on your board, then use the defined 12->100MHz PLL by changing the QSF file line:
````
#set_global_assignment -name QIP_FILE Clock_25to100.qip
set_global_assignment -name QIP_FILE Clock_12to100.qip
````


In the build/NEW_zpu_Toplevel.vhd:


````
1. Ensure the PLL is set to the correct one configured in the QSF file and the correct
   clock name is used throughout the file, ie:

   #mypll : entity work.Clock_25to100
   #port map
   #(
   #    inclk0            => CLOCK_25,
   #    c0                => sysclk,
   #    c1                => memclk,
   #    locked            => pll_locked
   #);
    mypll : entity work.Clock_12to100
    port map
    (
        inclk0            => CLOCK_12,
        c0                => sysclk,
        c1                => memclk,
        locked            => pll_locked
    );

2. Update the reset logic to use any switch or key on the board that you wish to be a
   reset:

    reset<=(not SW(0) xor KEY(0)) and pll_locked;

3. Ensure the correct clock frequency constant is setup in the generic of
   myVirtualToplevel:

   #myVirtualToplevel : entity work.zpu_soc
   #generic map
   #(
   #    SYSCLK_FREQUENCY => SYSCLK_E115_FREQ
   #)

    myVirtualToplevel : entity work.zpu_soc
    generic map
    (
        SYSCLK_FREQUENCY => SYSCLK_<NEW BOARD>_FREQ
    )

4. Ensure in the port map of myVirtualToplevel that unused components are set to open
   for outputs and '1' or '0' for the inactive state for inputs, ie:

    port map
    (    
        SYSCLK            => sysclk,
        MEMCLK            => memclk,
        RESET_IN          => reset,
    
        -- RS232
        UART_RX_0         => UART_RX_0,
        UART_TX_0         => UART_TX_0,
        UART_RX_1         => UART_RX_1,
        UART_TX_1         => UART_TX_1,
    
        -- SPI signals
        SPI_MISO          => '1',                              -- Allow the SPI interface not to be plumbed in.
        SPI_MOSI          => open,    
        SPI_CLK           => open,    
        SPI_CS            => open,    
    
        -- SD Card (SPI) signals
        SDCARD_MISO       => SDCARD_MISO,
        SDCARD_MOSI       => SDCARD_MOSI,
        SDCARD_CLK        => SDCARD_CLK,
        SDCARD_CS         => SDCARD_CS,
            
        -- PS/2 signals
        PS2K_CLK_IN       => '1', 
        PS2K_DAT_IN       => '1', 
        PS2K_CLK_OUT      => open, 
        PS2K_DAT_OUT      => open,    
        PS2M_CLK_IN       => '1',    
        PS2M_DAT_IN       => '1',    
        PS2M_CLK_OUT      => open,    
        PS2M_DAT_OUT      => open,    
    
        -- I²C signals
        I2C_SCL_IO        => open,
        I2C_SDA_IO        => open, 
    
        -- IOCTL Bus --
        IOCTL_DOWNLOAD    => open,                             -- Downloading to FPGA.
        IOCTL_UPLOAD      => open,                             -- Uploading from FPGA.
        IOCTL_CLK         => open,                             -- I/O Clock.
        IOCTL_WR          => open,                             -- Write Enable to FPGA.
        IOCTL_RD          => open,                             -- Read Enable from FPGA.
        IOCTL_SENSE       => '0',                              -- Sense to see if HPS accessing ioctl bus.
        IOCTL_SELECT      => open,                             -- Enable IOP control over ioctl bus.
        IOCTL_ADDR        => open,                             -- Address in FPGA to write into.
        IOCTL_DOUT        => open,                             -- Data to be written into FPGA.
        IOCTL_DIN         => (others => '0'),                  -- Data to be read into HPS.
    
        -- SDRAM signals which do not exist on the E115
        SDRAM_CLK         => open, --SDRAM_CLK,                -- sdram is accessed at 128MHz
        SDRAM_CKE         => open, --SDRAM_CKE,                -- clock enable.
        SDRAM_DQ          => open, --SDRAM_DQ,                 -- 16 bit bidirectional data bus
        SDRAM_ADDR        => open, --SDRAM_ADDR,               -- 13 bit multiplexed address bus
        SDRAM_DQM         => open, --SDRAM_DQM,                -- two byte masks
        SDRAM_BA          => open, --SDRAM_BA,                 -- two banks
        SDRAM_CS_n        => open, --SDRAM_CS,                 -- a single chip select
        SDRAM_WE_n        => open, --SDRAM_WE,                 -- write enable
        SDRAM_RAS_n       => open, --SDRAM_RAS,                -- row address select
        SDRAM_CAS_n       => open, --SDRAM_CAS,                -- columns address select
        SDRAM_READY       => open                              -- sd ready.
    );
````


### Connecting the Development board

1. In order to run the ZPU Evo iand it's software in basic form on the QMTECH board you need 2 USB to Serial (ie. [USB to Serial](https://www.amazon.co.uk/Laqiya-FT232RL-Converter-Adapter-Breakout/dp/B07H6XMC2X)) adapters and you wire them up according to the pinout as is defined in the \<zpu evo dir>/build/QMV_zpu.qsf file. Ensure the adapters are set to 3.3V. See Images section for colour coded wiring.
```shell
##============================================================
# UART
#============================================================
set_location_assignment PIN_AA14 -to UART_RX_0
set_location_assignment PIN_AA15 -to UART_TX_0
set_location_assignment PIN_Y15  -to UART_RX_1
set_location_assignment PIN_AB18 -to UART_TX_1
```
2. Open two Minicom/MobaXterm or equivalent serial consoles, setting the Serial port to one of the USB adapters in each. Setup the Baud Rate to 115200, with 8N1 formatting. Ensure auto line feed is enabled with Carriage Return.
3. Connect the USB Blaster between the QMTECH board and the PC.
4. Connect an SD Card Reader (ie. [SD Card Reader](https://www.amazon.co.uk/s?k=Micro+SD+Card+Reader+Module&i=computers&ref=nb_sb_noss)) to the QMTECH board according to the pinout as is defined in the \<zpu evo dir>/build/QMV_zpu.qsf file. See Images section for colour coded wiring.
```shell
##============================================================
# SD CARD
#============================================================
set_location_assignment PIN_Y17  -to SDCARD_MISO[0]
set_location_assignment PIN_AA18 -to SDCARD_MOSI[0]
set_location_assignment PIN_AA20 -to SDCARD_CLK[0]
set_location_assignment PIN_Y20  -to SDCARD_CS[0]
```
5. Insert the SD card created in the Software build above.
6. Open the Quartus Programmer (ie. Quartus Prime -> Tools -> Programmer), select the sof file via 'Add File' which will be in the directory \<zpu evo dir>/build/QMV_zpu.sof (QMV_EVO.sof if build was via Makefile) and setup the hardware via 'Hardware Setup'. 
7. Program the FPGA via 'Start' and on success, in the serial terminal window you will see the ZPUTA sign on message.

<br>

# Repository Structure

The GIT Repository is organised as per the build environment shown in the tables below.

### RTL

| Folder           | RTL File             | Description                                                  |
| ---------------- | -------------------- | ------------------------------------------------------------ |
| \<root>          | zpu_soc_pkg.tmpl.vhd | A templated version of zpu_soc_pkg.vhd used by the build/Makefile to configure and make a/all versions of the SoC. |
|                  | zpu_soc_pkg.vhd      | The SoC configuration file, this enables/disables components within the SoC. |
|                  | zpu_soc.vhd          | The SoC definition and glue logic between enabled components. |
| cpu/             | zpu_core_evo.vhd     | The ZPU Evo CPU.                                             |
|                  | zpu_core_flex.vhd    | The ZPU Flex CPU re-factored to keep the same style as the Evo and additional hardware debug output added. |
|                  | zpu_core_medium.vhd  | The ZPU Medium (4) CPU re-factored to keep the same style as the Evo and additional hardware debug output added. |
|                  | zpu_core_small.vhd   | The ZPU Small CPU re-factored to keep the same style as the Evo and additional hardware debug output added. |
|                  | zpu_pkg.vhd          | The CPU configuration, bus address width etc.                |
|                  | zpu_uart_debug.vhd   | A hardware debug serializer to output runtime data to a connected serial port. |
| devices/sysbus   | BRAM                 | Block RAM RTL                                                |
|                  | intr                 | Interrupt Controller                                         |
|                  | ps2                  | PS2 Keyboard/Mouse Controller                                |
|                  | RAM                  | Dual Port RAM                                                |
|                  | SDMMC                | SD Controller                                                |
|                  | spi                  | Serial Peripheral Interface Controller                       |
|                  | timer                | Timer                                                        |
|                  | uart                 | Full duplex cached UART Controller                           |
| devices/WishBone | I2C                  | I2C Controller                                               |
|                  | SRAM                 | Encapsulated Byte Addressable BRAM                           |
|                  | SDRAM                | Byte Addressable 32Bit SDRAM Controller                      |
| build            | CYC1000              | Quartus definition files and Top Level VHDL for the Trenz Electronic CYC1000 Cyclone 10LP development board. |
|                  | E115                 | Quartus definition files and Top Level VHDL for the Cyclone IV EP4CE115 DDR2 64BIT development board. |
|                  | QMV                  | Quartus definition files and Top Level VHDL for the QMTech Cyclone V development board. |
|                  | DE10                 | Quartus definition files and Top Level VHDL for the Altera DE10 development board as used in the MiSTer project. |
|                  | DE0                  | Quartus definition files and Top Level VHDL for the Altera DE0 development board. |
|                  | Clock_*              | Refactored Altera PLL definitions for various development board source clocks. These need to be made more generic for eventual inclusion of Xilinx fabric. |



### Software

| Folder  | Src File | Description                                                  |
| ------- | -------- | ------------------------------------------------------------ |
| apps    |          | The ZPUTA application can either have a feature embedded or as a separate standalone disk based applet in addition to extended applets. The purpose is to allow control of the ZPUTA application size according to available BRAM and SD card availability.<br/>All applets for ZPUTA are stored in this folder. |
| build   |          | Build tree output suitable for direct copy to an SD card.<br/> The initial bootloader and/or application as selected are compiled directly into a VHDL file for preloading in BRAM in the devices/sysbus/BRAM folder. |
| common  |          | Common C modules such as Elm Chan's excellent Fat FileSystem. |
| include |          | C Include header files.                                      |
| iocp    |          | A small bootloader/monitor application for initialization of the ZPU. Depending upon configuration this program can either boot an application from SD card or via the Serial Line and also provide basic tools such as memory examination. |
| startup |          | Assembler and Linker files for generating ZPU applications. These files are critical for defining how GCC creates and links binary images as well as providing the micro-code for ZPU instructions not implemented in hardware. |
| utils   |          | Some small tools for converting binary images into VHDL initialization data. |
| zputa   |          | The ZPU Test Application. This is an application for testing the ZPU and the SoC components. It can either be built as a single image for pre-loading into a BRAM via VHDL or as a standalone application loaded by the IOCP bootloader from an SD card. The services it provides can either be embedded or available on the SD card as applets depending on memory restrictions. |
|         | build.sh | Unix shell script to build IOCP, ZPUTA and Apps for a given design.<br/><br>NAME<br> &nbsp;&nbsp;&nbsp;&nbsp;build.sh&nbsp;-&nbsp;&nbsp;Shell&nbsp;script&nbsp;to&nbsp;build&nbsp;a&nbsp;ZPU&nbsp;program&nbsp;or&nbsp;OS.<br> <br> SYNOPSIS<br> &nbsp;&nbsp;&nbsp;&nbsp;build.sh&nbsp;[-dIOoMBsxAh]<br> <br> DESCRIPTION<br> <br> OPTIONS<br> &nbsp;&nbsp;&nbsp;&nbsp;-I&nbsp;<iocp&nbsp;ver>&nbsp;=&nbsp;0&nbsp;-&nbsp;Full,&nbsp;1&nbsp;-&nbsp;Medium,&nbsp;2&nbsp;-&nbsp;Minimum,&nbsp;3&nbsp;-&nbsp;Tiny&nbsp;(bootstrap&nbsp;only)<br> &nbsp;&nbsp;&nbsp;&nbsp;-O&nbsp;<os>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;=&nbsp;zputa,&nbsp;zos<br> &nbsp;&nbsp;&nbsp;&nbsp;-o&nbsp;<os&nbsp;ver>&nbsp;&nbsp;&nbsp;=&nbsp;0&nbsp;-&nbsp;Standalone,&nbsp;1&nbsp;-&nbsp;As&nbsp;app&nbsp;with&nbsp;IOCP&nbsp;Bootloader,<br> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;2&nbsp;-&nbsp;As&nbsp;app&nbsp;with&nbsp;tiny&nbsp;IOCP&nbsp;Bootloader,&nbsp;3&nbsp;-&nbsp;As&nbsp;app&nbsp;in&nbsp;RAM&nbsp;<br> &nbsp;&nbsp;&nbsp;&nbsp;-M&nbsp;<size>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;=&nbsp;Max&nbsp;size&nbsp;of&nbsp;the&nbsp;boot&nbsp;ROM/BRAM&nbsp;(needed&nbsp;for&nbsp;setting&nbsp;Stack).<br> &nbsp;&nbsp;&nbsp;&nbsp;-B&nbsp;<addr>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;=&nbsp;Base&nbsp;address&nbsp;of&nbsp;<os>,&nbsp;default&nbsp;-o&nbsp;==&nbsp;0&nbsp;:&nbsp;0x00000&nbsp;else&nbsp;0x01000&nbsp;<br> &nbsp;&nbsp;&nbsp;&nbsp;-A&nbsp;<addr>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;=&nbsp;App&nbsp;address&nbsp;of&nbsp;<os>,&nbsp;default&nbsp;0x0C000<br> &nbsp;&nbsp;&nbsp;&nbsp;-s&nbsp;<size>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;=&nbsp;Maximum&nbsp;size&nbsp;of&nbsp;an&nbsp;app,&nbsp;defaults&nbsp;to&nbsp;(BRAM&nbsp;SIZE&nbsp;-&nbsp;App&nbsp;Start&nbsp;Address&nbsp;-&nbsp;Stack&nbsp;Size)&nbsp;<br> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;if&nbsp;the&nbsp;App&nbsp;Start&nbsp;is&nbsp;located&nbsp;within&nbsp;BRAM&nbsp;otherwise&nbsp;defaults&nbsp;to&nbsp;0x10000.<br> &nbsp;&nbsp;&nbsp;&nbsp;-d&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;=&nbsp;Debug&nbsp;mode.<br> &nbsp;&nbsp;&nbsp;&nbsp;-x&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;=&nbsp;Shell&nbsp;trace&nbsp;mode.<br> &nbsp;&nbsp;&nbsp;&nbsp;-h&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;=&nbsp;This&nbsp;help&nbsp;screen.<br> <br> EXAMPLES<br> &nbsp;&nbsp;&nbsp;&nbsp;build.sh&nbsp;-O&nbsp;zputa&nbsp;-B&nbsp;0x00000&nbsp;-A&nbsp;0x50000<br> <br> EXIT&nbsp;STATUS<br> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;0&nbsp;&nbsp;&nbsp;&nbsp;The&nbsp;command&nbsp;ran&nbsp;successfully<br> <br> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;>0&nbsp;&nbsp;&nbsp;&nbsp;An&nbsp;error&nbsp;ocurred. |

<br>

## Quartus Prime in Docker 

Installing Quartus Prime can be tedious and time consuming, especially as the poorly documented linux installation can lead to a wrong mix or missing packages which results in a non-functioning installation. To ease the burden I have pieced together a Docker Image containing Ubuntu, the necessary packages and Quartus Prime 17.1.1.

1. Clone the repository:

    ````bash
    cd ~
    git clone https://github.com/pdsmart/zpu.git
    cd zpu/docker/QuartusPrime
    ````

    Current configuration will build a Lite version of Quartus Prime. If you want to install the Standard version, before building the docker image:
    
    ````
    Edit:        zpu/docker/QuartusPrime/Dockerfile.17.1.1
    Uncomment:   '#ARG QUARTUS=QuartusSetup-17.1.0.590-linux.run' 
    Comment out: 'ARG QUARTUS=QuartusLiteSetup-17.1.0.590-linux.run'.
    ````
   
    If you have a license file: 

    ````
    Copy: <your license file> to zpu/docker/QuartusPrime/files/license.dat
    Edit:  zpu/docker/QuartusPrime/run.sh
    Change: MAC_ADDR="02:50:dd:72:03:01" so that is has the MAC Address of your license file.
    ````

   Build the docker image:

    ````bash
    docker build -f Dockerfile.17.1.1 -t quartus-ii-17.1.1 .
    ````


2. Setup your X DISPLAY variable to point to your xserver:

    ````bash
    export DISPLAY=<x server ip or hostname>:<screen number>
    # ie. export DISPLAY=192.168.1.1:0
    ````

    On your X server machine, issue the command:

    ````bash
    xhost +
    # or xhost <ip of docker host> to maintain security on a non private network.
    ````

3. Setup your project directory accessible to Quartus.

    ````bash
    Edit:        zpu/docker/QuartusPrime/run.sh
    Change:      PROJECT_DIR_HOST=<location on your host you want to access from Quartus Prime>
    Change:      PROJECT_DIR_IMAGE=<location in Quartus Prime running container to where the above host directory is mapped>
    # ie. PROJECT_DIR_HOST=/srv/quartus
          PROJECT_DIR_IMAGE=/srv/quartus
    ````

3. Run the image using the provided bash script 'run.sh'. This script 

    ````bash
    ./run.sh
    ````

    This will start Quartus Prime and also an interactive bash shell.<br>On first start it currently asks for your license file, click 'Run the Quartus Prime software' and then OK. It will ask you this question everytime you start a new container albeit Im looking for a work around.<br>
    The host devices are mapped into the running docker container so that if you connect a USB Blaster it will be seen within the Programmer tool. As part of the installation I install the udev rules for USB-Blaster and USB-Blaster II as well as the Arrow USB-Blaster driver for use with the CYC1000 dev board.

4. To stop quartus prime:

    ````
    # Either exit the main Quartus Prime GUI window via File->Exit
    # or
    docker stop quartus
    ````
<br>

# Images

### Images of QMTECH Cyclone V wiring

![SD Card Wiring](https://github.com/pdsmart/ZPU/blob/master/docs/IMG_9837.jpg)
![UART 1 Wiring](https://github.com/pdsmart/ZPU/blob/master/docs/IMG_9838.jpg)
![UART 2 Wiring](https://github.com/pdsmart/ZPU/blob/master/docs/IMG_9839.jpg)
![QMTECH Cyclone V Board](https://github.com/pdsmart/ZPU/blob/master/docs/IMG_9840.jpg)
![Wiring on QMTECH Cyclone V Board](https://github.com/pdsmart/ZPU/blob/master/docs/IMG_9841.jpg)
<br>Above are the wiring connections for the QMTECH Cyclone V board as used in the Build section, colour co-ordinated for reference.
<br>

### Images of ZPUTA on a ZPU EVO CPU

![ZPUTA Performance Test](https://github.com/pdsmart/ZPU/blob/master/docs/ScreenZPU1.png)
Dhrystone and CoreMark performance tests of the ZPU Evo CPU. Depending on Fabric there are slight variations, these tests are on a Cyclone V CEFA chip, on a Cyclone IV CE I7 the results are 11.2DMIPS for Dhrystone and 19.1 for CoreMark.

![ZPUTA Help Screen Test](https://github.com/pdsmart/ZPU/blob/master/docs/ScreenZPU2.png)
Help screen for ZPUTA, help in this instance is an applet on the SD Card. A * before the description indicates the command is on SD, a - indicates the command is built-in.

![ZPUTA SD Directory](https://github.com/pdsmart/ZPU/blob/master/docs/ScreenZPU3.png)
SD Directory listings of all the compiled applets.

<br>
# Links

| Recommended Site                                                                               |
| ---------------------------------------------------------------------------------------------- |
| [Original Zylin ZPU repository](https://github.com/zylin/zpu)                                  |
| [Original Zylin GCC v3.4.2 toolchain](https://github.com/zylin/zpugcc)                         |
| [Flex ZPU repository](https://github.com/robinsonb5/ZPUFlex)                                   |
| [ZPUino and Eco System](http://papilio.cc/index.php?n=Papilio.ZPUinoIntroduction)              |
| [Wikipedia ZPU Reference](https://en.wikipedia.org/wiki/ZPU_\(microprocessor\))                |


<br>
# Credits

Where I have used or based any component on a 3rd parties design I have included the original authors copyright notice within the headers or given due credit. All 3rd party software, to my knowledge and research, is open source and freely useable, if there is found to be any component with licensing restrictions, it will be removed from this repository and a suitable link/config provided.


<br>
# Licenses

The original ZPU uses the Free BSD license and such the Evo is also released under FreeBSD. SoC components and other developments written by me are currently licensed using the GPL. 3rd party components maintain their original copyright notices.

### The FreeBSD license
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 
 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE ZPU PROJECT OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 The views and conclusions contained in the software and documentation are those of the authors and should not be interpreted as representing official policies, either expressed or implied, of the this project.

### The Gnu Public License v3
 The source and binary files in this project marked as GPL v3 are free software: you can redistribute it and-or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

 The source files are distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

 You should have received a copy of the GNU General Public License along with this program.  If not, see http://www.gnu.org/licenses/.


