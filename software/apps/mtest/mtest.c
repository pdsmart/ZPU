/////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            mtest.c
// Created:         September 2019
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
#include "mtest.h"

// Utility functions.
#include "tools.c"

// Version info.
#define VERSION      "v1.0"
#define VERSION_DATE "17/10/2019"
#define APP_NAME     "MTEST"

// Simple 8 bit memory write/read test.
void test8bit(uint32_t start, uint32_t end)
{
    // Locals.
    unsigned char* memPtr;
    unsigned long  count;
    uint8_t        data;

    xprintf( "\rWrite 8bit ascending test pattern...    " );
    memPtr = (unsigned char*)( start );
    data   = 0x00;
    count  = end - start;
    while ( count-- )
    {
        *memPtr++ = data++;
        if ( data >= 0xFF )
            data = 0x00;
    }

    xprintf( "\rRead 8bit ascending test pattern...     " );
    memPtr = (unsigned char*)( start );
    data   = 0x00;
    count  = end - start;
    while ( count-- )
    {
        if ( *memPtr != data )
            xprintf( "\rError (8bit) at 0x%08lX (%02x:%02x)\n", memPtr, *memPtr, data );
        *memPtr++;
        data++;
        if ( data >= 0xFF )
            data = 0x00;
    }
}

// Simple 16 bit memory write/read test.
void test16bit(uint32_t start, uint32_t end)
{
    // Locals.
    uint16_t  *memPtr;
    uint32_t   count;
    uint16_t   data;

    xprintf( "\rWrite 16bit ascending test pattern...    " );
    memPtr = (uint16_t*)( start );
    data   = 0x00;
    count  = end - start;
    while ( count > 0 )
    {
        *memPtr++ = data++;
        if ( data >= 0xFFFF )
            data = 0x00;
        count = count > 2 ? count -= 2 : 0;
    }

    xprintf( "\rRead 16bit ascending test pattern...     " );
    memPtr = (uint16_t*)( start );
    data   = 0x00;
    count  = end - start;
    while ( count > 0 )
    {
        if ( *memPtr != data )
            xprintf( "\rError (16bit) at 0x%08lX (%04x:%04x)\n", memPtr, *memPtr, data );
        *memPtr++;
        data++;
        if ( data >= 0xFFFF )
            data = 0x00;
        count = count > 2 ? count -= 2 : 0;
    }
}

// Simple 32 bit memory write/read test.
void test32bit(uint32_t start, uint32_t end)
{
    // Locals.
    uint32_t  *memPtr;
    uint32_t   count;
    uint32_t   data;

    xprintf( "\rWrite 32bit ascending test pattern...    " );
    memPtr = (uint32_t*)( start );
    data   = 0x00;
    count  = end - start;
    while ( count > 0 )
    {
        *memPtr++ = data++;
        if ( data >= 0xFFFFFFFE )
            data = 0x00;
        count = count > 4 ? count -= 4 : 0;
    }

    xprintf( "\rRead 32bit ascending test pattern...     " );
    memPtr = (uint32_t*)( start );
    data   = 0x00;
    count  = end - start;
    while ( count > 0 )
    {
        if ( *memPtr != data )
            xprintf( "\rError (32bit) at 0x%08lX (%08lx:%08lx)\n", memPtr, *memPtr, data );
        *memPtr++;
        data++;
        if ( data >= 0xFFFFFFFE )
            data = 0;
        count = count > 4 ? count -= 4 : 0;
    }
}

// Main entry and start point of a ZPUTA Application. Only 2 parameters are catered for and a 32bit return code, additional parameters can be added by changing the appcrt0.s
// startup code to add them to the stack prior to app() call.
//
// Return code is saved in _memreg by the C compiler, this is transferred to _memreg in ZPUTA in appcrt0.s prior to return.
//
uint32_t app(uint32_t param1, uint32_t param2)
{
    // Initialisation.
    //
    char           *ptr = (char *)param1;
    long           startAddr;
    long           endAddr;
    unsigned long  iterations;
    uint32_t       idx;

    // Get parameters or use defaults if not provided.
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
    if (!xatoi(&ptr,  &iterations))
    {
        iterations = 1;
    }

    // A very simple test, this needs to be updated with a thorough bit pattern and location test.
    xprintf( "Check memory addr 0x%08X to 0x%08X for %d iterations.\n", startAddr, endAddr, iterations );
    for(idx=0; idx < iterations; idx++)
    {
        test8bit(startAddr,  endAddr);
        test16bit(startAddr, endAddr);
        test32bit(startAddr, endAddr);
    }
    xputs("\n");

    return(0);
}
