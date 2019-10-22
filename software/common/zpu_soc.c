////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            zpu_soc.c
// Created:         January 2019
// Author(s):       Philip Smart
// Description:     ZPU System On a Chip utilities.
//                  A set of utilities specific to interaction with the ZPU SoC hardware.
//
// Credits:         
// Copyright:       (c) 2019 Philip Smart <philip.smart@net2net.org>
//
// History:         January 2019   - Initial script written.
//
/////////////////////////////////////////////////////////////////////////////////////////////////////////
// This source file is free software: you can redistribute it and#or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
/////////////////////////////////////////////////////////////////////////////////////////////////////////
#include "zpu-types.h"
#include "zpu_soc.h"
#include "uart.h"

// Global scope variables.
#ifdef USE_BOOT_ROM
    SOC_CONFIG                         cfgSoC;
#else
    SOC_CONFIG                         cfgSoC  = { .addrInsnBRAM   = INSN_BRAM_ADDR,
                                                   .sizeInsnBRAM   = INSN_BRAM_SIZE,
                                                   .addrBRAM       = BRAM_ADDR,
                                                   .sizeBRAM       = BRAM_SIZE,
                                                   .addrRAM        = RAM_ADDR,
                                                   .sizeRAM        = RAM_SIZE,
                                                   .resetVector    = CPU_RESET_ADDR,
                                                   .cpuMemBaseAddr = CPU_MEM_START,
                                                   .stackStartAddr = STACK_BRAM_ADDR,
                                                   .zpuId          = ZPU_ID,
                                                   .sysFreq        = CLK_FREQ,
                                                   .implSoCCFG     = 0,
                                                   .implInsnBRAM   = INSN_BRAM_IMPL,
                                                   .implBRAM       = BRAM_IMPL,
                                                   .implRAM        = RAM_IMPL,
                                                   .implDRAM       = DRAM_IMPL,
                                                   .implIOCTL      = IOCTL_IMPL,
                                                   .implPS2        = PS2_IMPL,
                                                   .implSPI        = SPI_IMPL,
                                                   .implSD         = IMPL_SD,
                                                   .sdCardNo       = SD_DEVICE_CNT,
                                                   .implIntrCtl    = INTRCTL_IMPL,
                                                   .implTimer1     = TIMER1_IMPL,
                                                   .timer1No       = TIMER1_TIMERS_CNT };
#endif


// Method to populate the Configuration structure, initially using in-built values from compile time
// which are overriden with values stored in the SoC if available.
void setupSoCConfig(void)
{
    // If the SoC Configuration register is implemented in the SoC, overwrite the compiled constants with those in the chip register.
    if( IS_IMPL_SOCCFG )
    {
        cfgSoC.addrInsnBRAM   = SOCCFG(SOCCFG_BRAMINSNADDR);
        cfgSoC.sizeInsnBRAM   = SOCCFG(SOCCFG_BRAMINSNSIZE);
        cfgSoC.addrBRAM       = SOCCFG(SOCCFG_BRAMADDR);
        cfgSoC.sizeBRAM       = SOCCFG(SOCCFG_BRAMSIZE);
        cfgSoC.addrRAM        = SOCCFG(SOCCFG_RAMADDR);
        cfgSoC.sizeRAM        = SOCCFG(SOCCFG_RAMSIZE);
        cfgSoC.resetVector    = SOCCFG(SOCCFG_CPURSTADDR);
        cfgSoC.cpuMemBaseAddr = SOCCFG(SOCCFG_CPUMEMSTART);
        cfgSoC.stackStartAddr = SOCCFG(SOCCFG_STACKSTART);
        cfgSoC.zpuId          = SOCCFG(SOCCFG_ZPU_ID);
        cfgSoC.sysFreq        = SOCCFG(SOCCFG_SYSFREQ);
        cfgSoC.implSoCCFG     = 1;
        cfgSoC.implInsnBRAM   = IS_IMPL_INSN_BRAM != 0;
        cfgSoC.implBRAM       = IS_IMPL_BRAM != 0;
        cfgSoC.implRAM        = IS_IMPL_RAM != 0;
        cfgSoC.implDRAM       = IS_IMPL_DRAM != 0;
        cfgSoC.implIOCTL      = IS_IMPL_IOCTL != 0;
        cfgSoC.implPS2        = IS_IMPL_PS2 != 0;
        cfgSoC.implSPI        = IS_IMPL_SPI != 0;
        cfgSoC.implSD         = IS_IMPL_SD != 0;
        cfgSoC.sdCardNo       = (uint8_t)SOCCFG_SD_DEVICES;
        cfgSoC.implIntrCtl    = IS_IMPL_INTRCTL != 0;
        cfgSoC.implTimer1     = IS_IMPL_TIMER1 != 0;
        cfgSoC.timer1No       = (uint8_t)SOCCFG_TIMER1_TIMERS;
#ifndef USE_BOOT_ROM
    }
#else
    } else
    {
        // Store builtin constants into structure which will be used when the SoC configuration module isnt implemented.
        cfgSoC.addrInsnBRAM   = INSN_BRAM_ADDR;
        cfgSoC.sizeInsnBRAM   = INSN_BRAM_SIZE;
        cfgSoC.addrBRAM       = BRAM_ADDR;
        cfgSoC.sizeBRAM       = BRAM_SIZE;
        cfgSoC.addrRAM        = RAM_ADDR;
        cfgSoC.sizeRAM        = RAM_SIZE;
        cfgSoC.resetVector    = CPU_RESET_ADDR;
        cfgSoC.cpuMemBaseAddr = CPU_MEM_START;
        cfgSoC.stackStartAddr = STACK_BRAM_ADDR;
        cfgSoC.zpuId          = ZPU_ID;
        cfgSoC.sysFreq        = CLK_FREQ;
        cfgSoC.implSoCCFG     = 0;
        cfgSoC.implInsnBRAM   = INSN_BRAM_IMPL;
        cfgSoC.implBRAM       = BRAM_IMPL ;
        cfgSoC.implRAM        = RAM_IMPL;
        cfgSoC.implDRAM       = DRAM_IMPL;;
        cfgSoC.implIOCTL      = IOCTL_IMPL;;
        cfgSoC.implPS2        = PS2_IMPL;
        cfgSoC.implSPI        = SPI_IMPL;
        cfgSoC.implSD         = IMPL_SD;
        cfgSoC.sdCardNo       = SD_DEVICE_CNT;
        cfgSoC.implIntrCtl    = INTRCTL_IMPL;
        cfgSoC.implTimer1     = TIMER1_IMPL;
        cfgSoC.timer1No       = TIMER1_TIMERS_CNT;
    }
#endif
}

// Method to show the current configuration via the primary uart channel.
//
#if !defined(FUNCTIONALITY) || FUNCTIONALITY <= 1
void showSoCConfig(void)
{
  #if defined(ZPUTA)
    xputs("SoC Configuration");
    if(cfgSoC.implSoCCFG)    { xputs(" (from SoC config)"); }
    xputs(":\nDevices implemented:\n");
    if(cfgSoC.implInsnBRAM)  { xprintf("    INSN BRAM (Start=%08X, Size=%08X).\n", cfgSoC.addrInsnBRAM, cfgSoC.sizeInsnBRAM); }
    if(cfgSoC.implBRAM)      { xprintf("    BRAM (Start=%08X, Size=%08X).\n", cfgSoC.addrBRAM, cfgSoC.sizeBRAM); }
    if(cfgSoC.implRAM || cfgSoC.implDRAM) { xprintf("    RAM (Start=%08X, Size=%08X).\n", cfgSoC.addrRAM, cfgSoC.sizeRAM); }
    if(cfgSoC.implIOCTL)     { xputs("    IOCTL\n"); }
    if(cfgSoC.implPS2)       { xputs("    PS2\n"); }
    if(cfgSoC.implSPI)       { xputs("    SPI\n"); }
    if(cfgSoC.implSD)        { xprintf("    SD Card (Devices=%02X).\n", (uint8_t) cfgSoC.sdCardNo); }
    if(cfgSoC.implIntrCtl)   { xputs("    INTERRUPT CONTROLLER\n"); }
    if(cfgSoC.implTimer1)    { xprintf("    TIMER1 (Timers=%01X).\n", (uint8_t)cfgSoC.timer1No); }
    xputs("Addresses:\n");
    xprintf("    CPU Reset Vector Address = %08X\n", cfgSoC.resetVector); 
    xprintf("    CPU Memory Start Address = %08X\n", cfgSoC.cpuMemBaseAddr);
    xprintf("    Stack Start Address      = %08X\n", cfgSoC.stackStartAddr);
    xprintf("    ZPU Id                   = %08X\n", cfgSoC.zpuId);
    xprintf("    System Clock Freq        = %08X\n", cfgSoC.sysFreq);
  #ifdef DRV_CFC
    xprintf("    CFC                      = %08X\n", DRV_CFC);
  #endif
  #ifdef DRV_MMC
    xprintf("    MMC                      = %08X\n", DRV_MMC);
  #endif    
  #else
    puts("SoC Configuration");
    if(cfgSoC.implSoCCFG)    { puts(" (from SoC config)"); }
    puts(":\nDevices implemented:\n");
    if(cfgSoC.implInsnBRAM)  { puts("    INSN BRAM (Start="); printdhex(cfgSoC.addrInsnBRAM); puts(", Size="); printdhex(cfgSoC.sizeInsnBRAM); puts(").\n"); }
    if(cfgSoC.implBRAM)      { puts("    BRAM (Start="); printdhex(cfgSoC.addrBRAM); puts(", Size="); printdhex(cfgSoC.sizeBRAM); puts(").\n"); }
    if(cfgSoC.implRAM || cfgSoC.implDRAM) { puts("    RAM (Start="); printdhex(cfgSoC.addrRAM); puts(", Size="); printdhex(cfgSoC.sizeRAM); puts(").\n"); }
    if(cfgSoC.implIOCTL)     { puts("    IOCTL\n"); }
    if(cfgSoC.implPS2)       { puts("    PS2\n"); }
    if(cfgSoC.implSPI)       { puts("    SPI\n"); }
    if(cfgSoC.implSD)        { puts("    SD Card (Devices="); printhexbyte((uint8_t) cfgSoC.sdCardNo); puts(").\n"); }
    if(cfgSoC.implIntrCtl)   { puts("    INTERRUPT CONTROLLER\n"); }
    if(cfgSoC.implTimer1)    { puts("    TIMER1 (Timers="); printnibble((uint8_t)cfgSoC.timer1No); puts(").\n"); }
    puts("Addresses:\n");
    puts("    CPU Reset Vector Address = "); printdhex(cfgSoC.resetVector); puts("\n");
    puts("    CPU Memory Start Address = "); printdhex(cfgSoC.cpuMemBaseAddr); puts("\n");
    puts("    Stack Start Address      = "); printdhex(cfgSoC.stackStartAddr); puts("\n");
    puts("    ZPU Id                   = "); printdhex(cfgSoC.zpuId); puts("\n");
    puts("    System Clock Freq        = "); printdhex(cfgSoC.sysFreq); puts("\n");
  #ifdef DRV_CFC
    puts("    CFC                      = "); printdhex(DRV_CFC); puts("\n");
  #endif
  #ifdef DRV_MMC
    puts("    MMC                      = "); printdhex(DRV_MMC); puts("\n");
  #endif    
  #endif
}

// Function to print out the ZPU Id in text form.
void printZPUId(uint32_t zpuId)
{
    switch((uint8_t)(zpuId >> 8))
    {
        case ZPU_ID_SMALL:
            puts("Small");
            break;

        case ZPU_ID_MEDIUM:
            puts("Medium");
            break;

        case ZPU_ID_FLEX:
            puts("Flex");
            break;

        case ZPU_ID_EVO:
            puts("EVO");
            break;

        case ZPU_ID_EVO_MINIMAL:
            puts("EVOmin");
            break;

        default:
            puts("Unknown");
            break;
    }
}
#endif
