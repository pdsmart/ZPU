/////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            mdump.c
// Created:         July 2019
// Author(s):       Philip Smart
// Description:     Standalone App for the ZPU test application.
//                  This program implements a loadable appliation which can be loaded from SD card by
//                  the ZPUTA application. The idea is that commands or programs can be stored on the
//                  SD card and executed by ZPUTA just like an OS such as Linux. The primary purpose
//                  is to be able to minimise the size of ZPUTA for applications where minimal ram is
//                  available.
//
// Credits:         
// Copyright:       (c) 2019 Philip Smart <philip.smart@net2net.org>
//
// History:         July 2019    - Initial framework creation.
//
// Notes:           See Makefile to enable/disable conditional components
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
#include <zstdio.h>
//#include <stdlib.h>
//#include <string.h>
#include <zpu-types.h>
#include "zpu_soc.h"
//#include "uart.h"
#include "interrupts.h"
#include "ff.h"            /* Declarations of FatFs API */
#include "diskio.h"
#include <zstdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>
#include "xprintf.h"
#include "utils.h"
#include "zputa_app.h"
#include "mdump.h"

// Utility functions.
#include "tools.c"

// Version info.
#define VERSION      "v1.0"
#define VERSION_DATE "18/07/2019"
#define APP_NAME     "MDUMP"

// Main entry and start point of a ZPUTA Application. Only 2 parameters are catered for and a 32bit return code, additional parameters can be added by changing the appcrt0.s
// startup code to add them to the stack prior to app() call.
//
// Return code is saved in _memreg by the C compiler, this is transferred to _memreg in ZPUTA in appcrt0.s prior to return.
//
uint32_t app(uint32_t param1, uint32_t param2)
{
    // Initialisation.
    //
    char      *ptr = (char *)param1;
    long      startAddr;
    long      endAddr;
    long      bitWidth;

    if (!xatoi(&ptr, &startAddr))
    {
        if(cfgSoC->implInsnBRAM)  { startAddr = cfgSoC->addrInsnBRAM; }
        else if(cfgSoC->implBRAM) { startAddr = cfgSoC->addrBRAM; }
        else if(cfgSoC->implRAM || cfgSoC->implDRAM) { startAddr = cfgSoC->addrRAM; }
        else { startAddr = cfgSoC->stackStartAddr - 512; }
    }
    if (!xatoi(&ptr,  &endAddr))
    {
        if(cfgSoC->implInsnBRAM)  { endAddr = cfgSoC->sizeInsnBRAM; }
        else if(cfgSoC->implBRAM) { endAddr = cfgSoC->sizeBRAM; }
        else if(cfgSoC->implRAM || cfgSoC->implDRAM) { endAddr = cfgSoC->sizeRAM; }
        else { endAddr = cfgSoC->stackStartAddr + 8; }
    }
    if (!xatoi(&ptr,  &bitWidth) || (bitWidth != 8 && bitWidth != 16 && bitWidth != 32))
    {
        bitWidth = 8;
    }
    xputs("Dump Memory\n");
    memoryDump(startAddr, endAddr, bitWidth, startAddr, 32);
    xputs("\n\nDumping completed.\n\n");

    return(0);
}
