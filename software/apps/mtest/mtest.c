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

// Fill memory with a constant.
void fillMemory(uint32_t startAddr, uint32_t endAddr, uint32_t value)
{
    // Locals.
    uint32_t  memAddr;

    for(memAddr=startAddr; memAddr < endAddr; memAddr+=4)
    {
        *(uint32_t *)(memAddr) = value;
    }
}

// Simple 8 bit memory write/read test.
void test8bit(uint32_t start, uint32_t end, uint32_t testsToDo)
{
    // Locals.
    unsigned char* memPtr;
    unsigned char* memPtr2;
    unsigned long  count;
    unsigned long  count2;
    uint8_t        data;
    uint32_t       errCnt = 0;

    if(testsToDo & 0x00000001)
    {
        xprintf( "\rR/W 8bit ascending test pattern...    " );
        memPtr = (unsigned char*)( start );
        data   = 0x00;
        count  = end - start;
        while( count-- && errCnt <= 20)
        {
            *memPtr = data;
            if( *memPtr != data )
            {
                xprintf( "\rError (8bit rwap) at 0x%08lX (%02x:%02x)\n", memPtr, *memPtr, data );
                if(errCnt++ == 20)
                    xprintf( "\rError count (8bit rwap) > 20, stopping test.\n");
            }
            *memPtr++;
            data++;
            if( data >= 0xFF )
                data = 0x00;
        }
    }

    if(testsToDo & 0x00000002)
    {
        xprintf( "\rR/W 8bit walking test pattern...    " );
        memPtr = (unsigned char*)( start );
        data   = 0x55;
        count  = end - start;
        errCnt = 0;
        while( count-- && errCnt <= 20)
        {
            *memPtr = data;
            if( *memPtr != data )
            {
                xprintf( "\rError (8bit rwwp) at 0x%08lX (%02x:%02x)\n", memPtr, *memPtr, data );
                if(errCnt++ == 20)
                    xprintf( "\rError count (8bit rwwp) > 20, stopping test.\n");
            }
            *memPtr++;
            if( data == 0x55 )
                data = 0xAA;
            else
                data = 0x55;
        }
    }

    if(testsToDo & 0x00000004)
    {
        xprintf( "\rWrite 8bit ascending test pattern...    " );
        memPtr = (unsigned char*)( start );
        data   = 0x00;
        count  = end - start;
        while( count-- )
        {
            *memPtr = data;
            if( *memPtr != data )
            {
                xprintf( "\rError (8bit wap) at 0x%08lX (%02x:%02x)\n", memPtr, *memPtr, data );
                if(errCnt++ == 20)
                    xprintf( "\rError count (8bit rwwp) > 20, stopping test.\n");
            }
            *memPtr++;
            data++;
            if( data >= 0xFF )
                data = 0x00;
        }

        xprintf( "\rRead 8bit ascending test pattern...     " );
        memPtr = (unsigned char*)( start );
        data   = 0x00;
        count  = end - start;
        errCnt = 0;
        while( count-- && errCnt <= 20)
        {
            if( *memPtr != data )
            {
                xprintf( "\rError (8bit ap) at 0x%08lX (%02x:%02x)\n", memPtr, *memPtr, data );
                if(errCnt++ == 20)
                    xprintf( "\rError count (8bit ap) > 20, stopping test.\n");
            } 
            *memPtr++;
            data++;
            if( data >= 0xFF )
                data = 0x00;
        }
    }

    if(testsToDo & 0x00000008)
    {
        xprintf( "\rWrite 8bit walking test pattern...    " );
        memPtr = (unsigned char*)( start );
        data   = 0x55;
        count  = end - start;
        while( count-- )
        {
            *memPtr++ = data;
            if( data == 0x55 )
                data = 0xAA;
            else
                data = 0x55;
        }

        xprintf( "\rRead 8bit walking test pattern...     " );
        memPtr = (unsigned char*)( start );
        data   = 0x55;
        count  = end - start;
        errCnt = 0;
        while( count-- && errCnt <= 20)
        {
            if( *memPtr != data )
            {
                xprintf( "\rError (8bit wp) at 0x%08lX (%02x:%02x)\n", memPtr, *memPtr, data );
                if(errCnt++ == 20)
                    xprintf( "\rError count (8bit wp) > 20, stopping test.\n");
            }
            *memPtr++;
            if( data == 0x55 )
                data = 0xAA;
            else
                data = 0x55;
        }
    }

    if(testsToDo & 0x00000010)
    {
        xprintf( "\r8bit echo and sticky bit test...     " );
        memPtr = (unsigned char*)( start );
        count  = end - start;
        errCnt = 0;
        fillMemory(start, end, 0x00000000);
        while( count-- && errCnt <= 20)
        {
            *memPtr = 0xFF;

            memPtr2 = (unsigned char*)( start );
            count2  = end - start;
            while( count2-- && errCnt <= 20)
            {
                if( *memPtr2 != 0x00 && *memPtr2 != *memPtr)
                {
                    xprintf( "\rError (8bit es) at 0x%08lx:0x%08lX (%02x:%02x)\n", memPtr, memPtr2, *memPtr2, 0x00 );
                    *memPtr2 = 0x00;
                    if(errCnt++ == 20)
                        xprintf( "\rError count (8bit es) > 20, stopping test.\n");
                }
                *memPtr2++;
            }
            *memPtr++ = 0x00;
        }
    }
}

// Simple 16 bit memory write/read test.
void test16bit(uint32_t start, uint32_t end, uint32_t testsToDo)
{
    // Locals.
    uint16_t      *memPtr;
    uint16_t      *memPtr2;
    uint32_t       count;
    uint32_t       count2;
    uint16_t       data;
    uint32_t       errCnt = 0;

    if(testsToDo & 0x00000004)
    {
        xprintf( "\rWrite 16bit ascending test pattern...    " );
        memPtr = (uint16_t*)( start );
        data   = 0x00;
        count  = end - start;
        while( count > 0 )
        {
            *memPtr++ = data++;
            if( data >= 0xFFFF )
                data = 0x00;
            count = count > 2 ? count -= 2 : 0;
        }

        xprintf( "\rRead 16bit ascending test pattern...     " );
        memPtr = (uint16_t*)( start );
        data   = 0x00;
        count  = end - start;
        while( count > 0 && errCnt <= 20)
        {
            if( *memPtr != data )
            {
                xprintf( "\rError (16bit ap) at 0x%08lX (%04x:%04x)\n", memPtr, *memPtr, data );
                if(errCnt++ == 20)
                    xprintf( "\rError count (16bit wp) > 20, stopping test.\n");
            }
            *memPtr++;
            data++;
            if( data >= 0xFFFF )
                data = 0x00;
            count = count > 2 ? count -= 2 : 0;
        }
    }

    if(testsToDo & 0x00000008)
    {
        xprintf( "\rWrite 16bit walking test pattern...    " );
        memPtr = (uint16_t*)( start );
        data   = 0xAA55;
        count  = end - start;
        while( count > 0 )
        {
            *memPtr++ = data;
            if( data == 0xAA55 )
                data = 0x55AA;
            else
                data = 0xAA55;
            count = count > 2 ? count -= 2 : 0;
        }

        xprintf( "\rRead 16bit walking test pattern...     " );
        memPtr = (uint16_t*)( start );
        data   = 0xAA55;
        count  = end - start;
        errCnt = 0;
        while( count > 0 && errCnt <= 20)
        {
            if( *memPtr != data )
            {
                xprintf( "\rError (16bit wp) at 0x%08lX (%04x:%04x)\n", memPtr, *memPtr, data );
                if(errCnt++ == 20)
                    xprintf( "\rError count (16bit wp) > 20, stopping test.\n");
            }
            *memPtr++;
            if( data == 0xAA55 )
                data = 0x55AA;
            else
                data = 0xAA55;
            count = count > 2 ? count -= 2 : 0;
        }
    }

    if(testsToDo & 0x00000010)
    {
        xprintf( "\r16bit echo and sticky bit test...     " );
        memPtr = (uint16_t *)( start );
        count  = end - start;
        errCnt = 0;
        fillMemory(start, end, 0x00000000);
        while( count > 0 && errCnt <= 20)
        {
            *memPtr = 0xFFFF;

            memPtr2 = (uint16_t *)( start );
            count2  = end - start;
            while( count2 > 0 && errCnt <= 20)
            {
                if( *memPtr2 != 0x0000 && *memPtr2 != *memPtr)
                {
                    xprintf( "\rError (16bit es) at 0x%08lx:0x%08lX (%04x:%04x)\n", memPtr, memPtr2, *memPtr2, 0x0000 );
                    *memPtr2 = 0x0000;
                    if(errCnt++ == 20)
                        xprintf( "\rError count (16bit es) > 20, stopping test.\n");
                }
                *memPtr2++;
                count2 = count2 > 2 ? count2 -= 2 : 0;
            }
            count = count > 2 ? count -= 2 : 0;
            *memPtr++ = 0x0000;
        }
    }
}

// Simple 32 bit memory write/read test.
void test32bit(uint32_t start, uint32_t end, uint32_t testsToDo)
{
    // Locals.
    uint32_t      *memPtr;
    uint32_t      *memPtr2;
    uint32_t       count;
    uint32_t       count2;
    uint32_t       data;
    uint32_t       errCnt = 0;

    if(testsToDo & 0x00000004)
    {
        xprintf( "\rWrite 32bit ascending test pattern...    " );
        memPtr = (uint32_t*)( start );
        data   = 0x00;
        count  = end - start;
        while( count > 0 )
        {
            *memPtr++ = data++;
            if( data >= 0xFFFFFFFE )
                data = 0x00;
            count = count > 4 ? count -= 4 : 0;
        }

        xprintf( "\rRead 32bit ascending test pattern...     " );
        memPtr = (uint32_t*)( start );
        data   = 0x00;
        count  = end - start;
        while( count > 0 && errCnt <= 20)
        {
            if( *memPtr != data )
            {
                xprintf( "\rError (32bit ap) at 0x%08lX (%08lx:%08lx)\n", memPtr, *memPtr, data );
                if(errCnt++ == 20)
                    xprintf( "\rError count (32bit wp) > 20, stopping test.\n");
            }
            *memPtr++;
            data++;
            if( data >= 0xFFFFFFFE )
                data = 0;
            count = count > 4 ? count -= 4 : 0;
        }
    }

    if(testsToDo & 0x00000008)
    {
        xprintf( "\rWrite 32bit walking test pattern...    " );
        memPtr = (uint32_t*)( start );
        data   = 0xAA55AA55;
        count  = end - start;
        while( count > 0 )
        {
            *memPtr++ = data;
            if( data == 0xAA55AA55 )
                data   = 0x55AA55AA;
            else
                data   = 0xAA55AA55;
            count = count > 4 ? count -= 4 : 0;
        }

        xprintf( "\rRead 32bit walking test pattern...     " );
        memPtr = (uint32_t*)( start );
        data   = 0x00;
        data   = 0xAA55AA55;
        count  = end - start;
        errCnt = 0;
        while( count > 0 && errCnt <= 20)
        {
            if( *memPtr != data )
            {
                xprintf( "\rError (32bit wp) at 0x%08lX (%08lx:%08lx)\n", memPtr, *memPtr, data );
                if(errCnt++ == 20)
                    xprintf( "\rError count (32bit wp) > 20, stopping test.\n");
            }
            *memPtr++;
            if( data == 0xAA55AA55 )
                data   = 0x55AA55AA;
            else
                data   = 0xAA55AA55;
            count = count > 4 ? count -= 4 : 0;
        }
    }

    if(testsToDo & 0x00000010)
    {
        xprintf( "\r32bit echo and sticky bit test...     " );
        memPtr = (uint32_t *)( start );
        count  = end - start;
        errCnt = 0;
        fillMemory(start, end, 0x00000000);
        while( count > 0 && errCnt <= 20)
        {
            *memPtr = 0xFFFFFFFF;

            memPtr2 = (uint32_t *)( start );
            count2  = end - start;
            while( count2 > 0 && errCnt <= 20)
            {
                if( *memPtr2 != 0x00000000 && *memPtr2 != *memPtr)
                {
                    xprintf( "\rError (32bit es) at 0x%08lx:0x%08lX (%08x:%08x)\n", memPtr, memPtr2, *memPtr2, 0x00000000 );
                    *memPtr2 = 0x00000000;
                    if(errCnt++ == 20)
                        xprintf( "\rError count (32bit es) > 20, stopping test.\n");
                }
                *memPtr2++;
                count2 = count2 > 4 ? count2 -= 4 : 0;
            }
            count = count > 4 ? count -= 4 : 0;
            *memPtr++ = 0x00000000;
        }
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
    long           testsToDo;
    unsigned long  iterations;
    uint32_t       idx;

    // Get parameters or use defaults if not provided.
    if(!xatoi(&ptr, &startAddr))
    {
        if(cfgSoC->implInsnBRAM)      { startAddr = cfgSoC->addrInsnBRAM; }
        else if(cfgSoC->implBRAM)     { startAddr = cfgSoC->addrBRAM; }
        else if(cfgSoC->implRAM)      { startAddr = cfgSoC->addrRAM; }
        else if(cfgSoC->implSDRAM)    { startAddr = cfgSoC->addrSDRAM; }
        else if(cfgSoC->implWBSDRAM)  { startAddr = cfgSoC->addrWBSDRAM; }
        else { startAddr = cfgSoC->stackStartAddr - 512; }
    }
    if(!xatoi(&ptr,  &endAddr))
    {
        if(cfgSoC->implInsnBRAM)      { endAddr = cfgSoC->sizeInsnBRAM; }
        else if(cfgSoC->implBRAM)     { endAddr = cfgSoC->sizeBRAM; }
        else if(cfgSoC->implRAM)      { endAddr = cfgSoC->sizeRAM; }
        else if(cfgSoC->implSDRAM)    { endAddr = cfgSoC->sizeSDRAM; }
        else if(cfgSoC->implWBSDRAM)  { endAddr = cfgSoC->sizeWBSDRAM; }
        else { endAddr = cfgSoC->stackStartAddr + 8; }
    }
    if(!xatoi(&ptr,  &iterations))
    {
        iterations = 1;
    }
    if(!xatoi(&ptr,  &testsToDo))
    {
        // Default to all tests.
        testsToDo = 0xFFFFFFFF;
    }

    // A very simple test, this needs to be updated with a thorough bit pattern and location test.
    xprintf( "Check memory addr 0x%08X to 0x%08X for %d iterations.\n", startAddr, endAddr, iterations );
    for(idx=0; idx < iterations; idx++)
    {
        if(testsToDo & 0x00001000)
        {
            test8bit(startAddr,  endAddr, testsToDo);
        }
        if(testsToDo & 0x00002000)
        {
            test16bit(startAddr, endAddr, testsToDo);
        }
        if(testsToDo & 0x00004000)
        {
            test32bit(startAddr, endAddr, testsToDo);
        }
    }
    xputs("\n");

    return(0);
}
