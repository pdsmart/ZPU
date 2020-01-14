/////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            mperf.c
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
#include "mperf.h"

// Utility functions.
#include "tools.c"

// Version info.
#define VERSION      "v1.1"
#define VERSION_DATE "23/12/2019"
#define APP_NAME     "MPERF"


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
    long      xferSize;
    uint32_t  writePerf;
    uint32_t  readPerf;
    uint32_t  basePerf;
    uint32_t  memAddr;
    uint32_t  xferCount;
    uint32_t  writePerfAdj;
    uint32_t  readPerfAdj;
    uint32_t  xferSizeAdj;
    uint32_t  writePerfMBs;
    uint32_t  readPerfMBs;
    uint32_t  memReadWord  = 0;
    uint16_t  memReadHWord = 0;
    uint8_t   memReadByte  = 0;


    if (!xatoi(&ptr, &startAddr))
    {
        xprintf("Illegal <start addr> value.\n");
    } else if (!xatoi(&ptr, &endAddr))
    {
        xprintf("Illegal <end addr> value.\n");
    } else
    {
        xatoi(&ptr,  &bitWidth);
        if(bitWidth != 8 && bitWidth != 16 && bitWidth != 32)
        {
            bitWidth = 32;
        }
        if(!xatoi(&ptr,  &xferSize))
        {
            xferSize = 10;
        }

        xprintf("Testing Memory Performance in range: %08lx:%08lx, write width:%d, size:%dMB...", startAddr, endAddr, bitWidth, xferSize);
        bitWidth /= 8;

        memAddr   = startAddr;
        xferCount = xferSize * (1024*1024);
        switch(bitWidth)
        {
            case 1:
                TIMER_MILLISECONDS_UP = 0;
                while(xferCount > 0)
                {
                    *(uint8_t *)(memAddr) = 0xAA;
                    memAddr   += 1;
                    xferCount -= 1;
                    if(memAddr > endAddr) { memAddr = startAddr; }
                }
                writePerf = TIMER_MILLISECONDS_UP;
                break;
            case 2:
                TIMER_MILLISECONDS_UP = 0;
                while(xferCount > 0)
                {
                    *(uint16_t *)(memAddr) = 0xAA55;
                    memAddr   += 2;
                    xferCount -= 2;
                    if(memAddr > endAddr) { memAddr = startAddr; }
                }
                writePerf = TIMER_MILLISECONDS_UP;
                break;
            case 4:
            default:
                TIMER_MILLISECONDS_UP = 0;
                while(xferCount > 0)
                {
                    *(uint32_t *)(memAddr) = 0xAA55AA55;
                    memAddr   += 4;
                    xferCount -= 4;
                    if(memAddr > endAddr) { memAddr = startAddr; }
                }
                writePerf = TIMER_MILLISECONDS_UP;
                break;
        }
        memAddr   = startAddr;
        xferCount = xferSize * (1024*1024);
        switch(bitWidth)
        {
            case 1:
                TIMER_MILLISECONDS_UP = 0;
                while(xferCount > 0)
                {
                    memReadByte = *(uint8_t *)(memAddr);
                    memAddr   += 1;
                    xferCount -= 1;
                    if(memAddr > endAddr) { memAddr = startAddr; }
                }
                readPerf = TIMER_MILLISECONDS_UP;
                break;

            case 2:
                TIMER_MILLISECONDS_UP = 0;
                while(xferCount > 0)
                {
                    memReadHWord = *(uint16_t *)(memAddr);
                    memAddr   += 2;
                    xferCount -= 2;
                    if(memAddr > endAddr) { memAddr = startAddr; }
                }
                readPerf = TIMER_MILLISECONDS_UP;
                break;

            case 4:
            default:
                TIMER_MILLISECONDS_UP = 0;
                while(xferCount > 0)
                {
                    memReadWord = *(uint32_t *)(memAddr);
                    memAddr   += 4;
                    xferCount -= 4;
                    if(memAddr > endAddr) { memAddr = startAddr; }
                }
                readPerf = TIMER_MILLISECONDS_UP;
                break;
        }

        // Basemark time, ie. all the actions without the memory operation to ascertain the ZPU stack and code overhead.
        memAddr   = startAddr;
        xferCount = xferSize * (1024*1024);
        switch(bitWidth)
        {
            case 1:
                TIMER_MILLISECONDS_UP = 0;
                while(xferCount > 0)
                {
                    memAddr   += 1;
                    xferCount -= 1;
                    if(memAddr > endAddr) { memAddr = startAddr; }
                }
                basePerf = TIMER_MILLISECONDS_UP;
                break;

            case 2:
                TIMER_MILLISECONDS_UP = 0;
                while(xferCount > 0)
                {
                    memAddr   += 2;
                    xferCount -= 2;
                    if(memAddr > endAddr) { memAddr = startAddr; }
                }
                basePerf = TIMER_MILLISECONDS_UP;
                break;

            case 4:
            default:
                TIMER_MILLISECONDS_UP = 0;
                while(xferCount > 0)
                {
                    memAddr   += 4;
                    xferCount -= 4;
                    if(memAddr > endAddr) { memAddr = startAddr; }
                }
                basePerf = TIMER_MILLISECONDS_UP;
                break;
        }

        writePerfAdj = writePerf - basePerf;              // Actual time spent in write portion of loop.
        readPerfAdj  = readPerf  - basePerf;              // Actual time spent in read portion of loop.
        xferSizeAdj  = xferSize * 1024 * 1024;            // Transfer size adjusted to calculate milliseconds per MB transfer.
        writePerfMBs = (xferSizeAdj / writePerfAdj)/1000; // Round value of MB/s for write.
        readPerfMBs  = (xferSizeAdj / readPerfAdj)/1000;  // Round value of MB/s for read.

        xprintf("\nWrite %dMB in mS: %ld\n",          xferSize, writePerf);
        xprintf("Read  %dMB in mS: %ld\n",            xferSize, readPerf);
        xprintf("Base  %dMB in mS: %ld\n",            xferSize, basePerf);
        xprintf("\nWrite performance: %d.%d MB/s\n",  writePerfMBs, (xferSizeAdj / writePerfAdj) - (writePerfMBs * 1000));
        xprintf("Read performance:  %d.%d MB/s\n",    readPerfMBs,  (xferSizeAdj / readPerfAdj) -  (readPerfMBs * 1000));
    }

    return(0);
}
