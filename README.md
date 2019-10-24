## Foreword

This document is a work in progress with the intention of it ending up as a comprehensive user guide. The same goes for the ZPU Evo and SoC RTL as both are evolving as I further the emulator project it was originally destined to go into and any improvements/deficiencies corrected.



## Overview

The ZPU is a 32bit Stack based microprocessor and was designed by Øyvind Harboe from Zylin AS ( https://opensource.zylin.com/ ) and original documentation can be found on the Zylin/OpenCore website or Wikipedia ( https://en.wikipedia.org/wiki/ZPU_(microprocessor) ). It is a microprocessor intended for FPGA embedded applications with minimal logic element and BRAM usage with the sacrifice of speed of execution. 

Zylin produced two designs which it made open source, namely the Small and Medium ZPU versions. Additional designs were produced by external developers such as the Flex and ZPUino variations, each offering enhancements to the original design such as Wishbone interface, performance etc.

This document describes another design which I like to deem as the ZPU Evo(lution) model whose focus is on performance, connectivity and instruction expansion. This came about as I needed a CPU for an emulator of a vintage computer i am writing which would act as the IO processor to provide Menu, Peripheral and SD services.

An example of the performance of the ZPU Evo can be seen using CoreMark which returns a value of 19.1 @ 100MHz on Altera fabric using BRAM and for Dhrystone 11.2DMIPS. Connectivity can be seen via implementation of both System and Wishbone buses, allowing for connection of many opensource IP devices. Instruction expansion can be seen by the inclusion of a close coupled L1 cache where multiple instruction bytes are sourced and made available to the CPU which in turn can be used for optimization (ie. upto 5 IM instructions executed in 1 cycle) or for extended multi-byte instructions (ie. implementation of a LoaD Increment Repeat instruction). There is room for a lot more improvements such as stack cache, SDRAM to L2 burst mode, parallel instruction execution (ie. and + neqbranch) which are on my list.



## ZPU Evo

The ZPU Evo follows on from the ZPU Medium and Flex and areas of the code are similar, for example the instruction decoding. The design differs though due to caching and implementation of a Memory Transaction Processor where all Memory/IO operations (except for direct Instruction reads if dual-port instruction bus is enabled) are routed. The original CPU's all handled their memory requirements in-situ or part of the state machine whereas the Evo submits a request to the MXP whenever a memory operation is required.

The following sections indicate some of the features and changes to original ZPU designs.

#### Bus structure

The ZPU has a linear address space with all memory and IO devices directly addressable within this space. Existing ZPU designs either provide a system bus or a wishbone bus whereas the Evo provides both. The ZPU Evo creates up to two distinct regions within the address space depending on configuration, to provide a *system bus* and a *wishbone bus*.

All models have the system bus instantiated which starts at cpu address 0 and expands up-to the limit imposed by the configurable maximum address bit (ie. 0x000000 - 0xFFFFFF for 24bit). A dedicated memory mapped IO region is set aside at the top of the address space (albeit it could quite easily be in any location) ie. 0xFF0000 - 0xFFFFFF.

If configured, a wishbone bus can be instantiated and this extends the maximum address bit by 1 (ie. 0x1000000 - 0x1FFFFFF for 24bit example). This in effect creates 2 identical regions, the lower being controlled via the system bus, the upper via the wishbone bus. As per the system bus, the upper area of the wishbone address space is reserved for IO devices.

A third bus can be configured, which is for instruction reads only. This bus typically shadows the system bus in memory region but is deemed to be connected to fast access memory for reading of instructions without the need for L2 Cache. This would typically be the 2nd port of a dual-port BRAM block with the 1st port connected to the system bus. 

#### L1 Cache

In order to gain performance but more especially for instruction optimisations and extended instructions, an L1 cache is implemented using registers. Using registers consumes fabric space so should be very small but it allows random access in a single cycle which is needed for example if compacting a 32bit IM load (which can be 5 instructions) into a single cycle. Also for extended instructions, the first byte indicates an extended instruction and the following 1-5 bytes defines the instruction which is then executed in a single cycle.

#### L2 Cache

Internal BRAM (on-board Block RAM within the FPGA) doesn't need an L2 Cache as it's access time is 1-2 cycles. As BRAM is a limited resource it is assumed external RAM or SDRAM will be used which is much slower and this needs to be cached to increase throughput. The L2 Cache is used for this purpose, to read ahead a block of external RAM and feed the L1 Cache as needed. On analysis, the C programs generated by GCC are typically loops and calls within a local area (unless using large libraries), so implementing a simple direct mapping cache between external RAM and BRAM (used for the L2 Cache) indexed relative to the Program Counter is sufficient to keep the CPU from stalling most of the time.

#### Instruction Set

A feature of the ZPU is it's use of a minimal fixed set of hardware implemented instructions and a soft set of additional instructions which are implemented in pseudo micro-code (ie. the fixed set of instructions). This is achieved by 32byte vectors in the region 0x0000 - 0x0400 and each soft instruction branches to the vector if it is not implemented in hardware. The benefit is reduced FPGA resources but the penalty is performance.

The ZPU Evo implements all instructions in hardware but this can be adjusted in the configuration to use soft instructions if required in order to conserve FPGA resources. This allows for a balance of resources versus performance. Ultimately though, if resources are tight then the use of the Small/Flex ZPU models may be a better choice.

In addition to the original instructions, a mechanism exists to extend the instruction set using multi-byte instructions of the format:-

***Extend Instruction,<new insn[7:2]+ParamSize[1:0]>,[byte],[byte],[byte],[byte]***

Where ParamSize = 00 - No parameter bytes
                                    01 - 8 bit parameter
                                    10 - 16 bit parameter
                                    11 - 32 bit parameter

Some extended instructions are under development (ie. LDIR) an exact opcode value and extended instruction set has not yet been fully defined. The GNU AS assembler will be updated with these instructions so they can be invoked within a C program and eventually if they have benefit to C will be migrated into the GCC compiler (ie. ADD32/DIV32/MULT32/LDIR/LDDR as from what I have seen, these will have a big impact on CoreMark/Dhrystone tests).

Implemented Instructions

![](/dvlp/Projects/dev/github/zpu/ImplInstructions.png)

#### Hardware Variable Byte Write

In the original ZPU designs there was scope but not the implementation to allow the ZPU to perform byte/half-word/full-word writes. Either the CPU always had to perform 32bit Word aligned operations or it performed the operation in micro-code.

In the Evo, hardware was implemented (build time selectable) to allow Byte and Half-Word writes and also hardware Read-Update-Write operations. If the hardware Byte/Half-Word logic is not enabled then it falls back to the 32bit Word Read-Update-Write logic. Both methods have performance benefits, the latter taking 3 cycles longer.

#### Hardware Debug Serializer

In order to debug the CPU or just provide low level internal operating information, a cached UART debug module is implemented. Currently this is only for output but has the intention to be tied into the IOCP for in-situ debugging when Simulation/Signal-Tap is not available.

Embedded within the CPU RTL are statements which issue snapshot information to the serialiser, if  enabled in the configuration along with the information level. This is then serialized and output to a connected terminal. A snapshot of the output information can be seen below (with manual comments):

| 000477 01ffec 00001ae4 00000000 70.17 04770484 046c047c 08f0046c 0b848015 17700500 05000500 05001188 11ef2004  <br/><br/><u>Break Point - Illegal instruction</u><br/>000478 01ffe8 00001ae4 00001ae4 00.05 04780484 046c0478 08f0046c 0b888094 05000500 05000500 118811ef 20041188  <br/><br/><u>L1 Cache Dump</u><br/>000478 (480)-> 11 e2 2a 51 11 a0 11 8f <-(483) (004)->11 ed 20 04 05 00 05 00 05 00 05 00 05 00 05 00 20 (46c)->04 11 b5 11 e4 17 70 <-(46f)<br/>      (004)-> 11 ed 20 04 05 00 05 00 05 00 05 00 05 00 05 00 20 (46c)->04 11 b5 11 e4 17 70 11 b6 11 c4 2d 27 11 8b <-(473)<br/>       05 00 05 00 05 00 05 00 (46c)->20 04 11 b5 11 e4 17 70 11 b6 11 c4 2d 27 11 8b 1c 38 11 80 17 71 17 70 -<(477)<br/>(46c)->20 04 11 b5 11 e4 17 70 11 b6 11 c4 2d 27 11 8b 1c 38 11 80 17 71 17 70 -<(477) 05 00 05 00 05 00 05 00 <br/>(470)->11 b6 11 c4 2d 27 11 8b 1c 38 11 80 17 71 17 70 <-(477) -> 05 00 05 00 05 00 05 00 (47c)->11 88 11 ef 20 04 11 88 <-(47f)<br/>(474)->1c 38 11 80 17 71 17 70 05 00 05 00 05 00 05 00 11 88 11 ef 20 04 11 88 11 e2 2a 51 11 a0 11 8f <br/>       05 00 05 00 05 00 05 00 11 88 11 ef 20 04 11 88 11 e2 2a 51 11 a0 11 8f 11 ed 20 04 05 00 05 00 <br/>       11 88 11 ef 20 04 11 88 11 e2 2a 51 11 a0 11 8f 11 ed 20 04 05 00 05 00 05 00 05 00 05 00 05 00 <br/><u>L2 Cache Dump</u><br/>000000 88 08 8c 08 ed 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 <br/>000020 88 08 8c 08 90 08 0b 0b 0b 88 80 08 2d 90 0c 8c 0c 88 0c 04 00 00 00 00 00 00 00 00 00 00 00 00 <br/>000040 71 fd 06 08 72 83 06 09 81 05 82 05 83 2b 2a 83 ff ff 06 52 04 00 00 00 00 00 00 00 00 00 00 00 |
| :----------------------------------------------------------- |
|                                                              |

All critical information such as current instruction being executed (or not if stalled), Signals/Flags, L1/L2 Cache contents and Memory contents can be output.



## System On a Chip

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



## GIT Folder Structure

#### RTL Structure

| Folder           | RTL File             | Description                                                  |
| ---------------- | -------------------- | ------------------------------------------------------------ |
| < root >         | zpu_soc_pkg.tmpl.vhd | A templated version of zpu_soc_pkg.vhd used by the build/Makefile to configure and make a/all versions of the SoC. |
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



#### Software Structure

| Folder  | Module   | Description                                                  |
| ------- | -------- | ------------------------------------------------------------ |
| apps    |          | The ZPUTA application can either have a feature embedded or as a separate standalone disk based applet in addition to extended applets. The purpose is to allow control of the ZPUTA application size according to available BRAM and SD card availability.<br/>All applets for ZPUTA are stored in this folder. |
| build   |          | Build tree output suitable for direct copy to an SD card.<br/> The initial bootloader and/or application as selected are compiled directly into a VHDL file for preloading in BRAM in the devices/sysbus/BRAM folder. |
| common  |          | Common C modules such as Elm Chan's excellent Fat FileSystem. |
| include |          | C Include header files.                                      |
| iocp    |          | A small bootloader/monitor application for initialization of the ZPU. Depending upon configuration this program can either boot an application from SD card or via the Serial Line and also provide basic tools such as memory examination. |
| startup |          | Assembler and Linker files for generating ZPU applications. These files are critical for defining how GCC creates and links binary images as well as providing the micro-code for ZPU instructions not implemented in hardware. |
| utils   |          | Some small tools for converting binary images into VHDL initialization data. |
| zputa   |          | The ZPU Test Application. This is an application for testing the ZPU and the SoC components. It can either be built as a single image for pre-loading into a BRAM via VHDL or as a standalone application loaded by the IOCP bootloader from an SD card. The services it provides can either be embedded or available on the SD card as applets depending on memory restrictions. |
|         | build.sh | Unix shell script to build IOCP, ZPUTA and Apps for a given design.<br/>NAME<br/>    build.sh -  Shell script to build a ZPU program or OS.<br/><br/>SYNOPSIS<br/>    build.sh [-dOBAh]<br/><br/>DESCRIPTION<br/><br/>OPTIONS<br/>    -I < iocp ver > = 0 - Full, 1 - Medium, 2 - Minimum, 3 - Tiny (bootstrap only)<br/>    -O < os >       = zputa, zos<br/>    -o < os ver >   = 0 - Standalone, 1 - As app with IOCP Bootloader,<br/>                    2 - As app with tiny IOCP Bootloader, 3 - As app in RAM<br/>    -B < addr >     = Base address of < os >, default 0x01000<br/>    -A < addr >     = App address of < os >, default 0x0C000<br/>    -d            = Debug mode.<br/>    -h            = This help screen.<br/><br/>EXAMPLES<br/>    build.sh -I 3 -O zputa -o 2 -B 0x00000 -A 0x50000<br/><br/>EXIT STATUS<br/>     0    The command ran successfully<br/>     >0    An error ocurred. |



#### Memory Maps

The I/O Control Program (IOCP) is basically a bootloader, it can operate standalone or as the first stage in booting an application. At the time of writing the following memory maps have been defined in the build.sh and parameterisation of the IOCP/ZPUTA/RTL but any other is possible by adjusting the parameters.

The memory maps are as follows:-

Tiny - IOCP is the smallest size possible to boot from SD Card. It is useful for a SoC configuration where there is limited BRAM and the applications loaded from the SD card would potentially run in external RAM.

Minimum - Full - IOCP has various inbuilt functions, such as application upload from serial port, memory edit/exam.

![](/dvlp/Projects/dev/github/zpu/IOCPMemoryMap.png)



For ZPUTA, it can either be configured to be the boot application (ie. no IOCP) or it can be configured as an App booted by IOCP. Depending upon how ZPUTA is built. it can have applets (portions of its functionality created as dedicated executables on the SD card) or standalone with all functionality inbuilt. The former is used when there is limited memory or a set of loadable programs is desired.

![](/dvlp/Projects/dev/github/zpu/ZPUTAMemoryMap.png)





## Credits

Where I have used or based any component on a 3rd parties design I have included the original authors copyright notice within the headers or given due credit. Some devices are purely 3rd party (ie. I2C) and they remain untouched carrying the original copyright header.



## Licenses

The original ZPU uses the Free BSD license and such the Evo is also released under FreeBSD. SoC components and other developments written by me are currently licensed using the GPL. 3rd party components maintain their original copyright notices.



## Links

| Reference                           | URL                                                      |
| ----------------------------------- | -------------------------------------------------------- |
| Original Zylin ZPU repository       | https://github.com/zylin/zpu                             |
| Original Zylin GCC v3.4.2 toolchain | https://github.com/zylin/zpugcc                          |
| Flex ZPU repository                 | https://github.com/robinsonb5/ZPUFlex                    |
| ZPUino and Eco System               | http://papilio.cc/index.php?n=Papilio.ZPUinoIntroduction |
| Wikipedia ZPU Reference             | https://en.wikipedia.org/wiki/ZPU_(microprocessor)       |