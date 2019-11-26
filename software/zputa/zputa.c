/////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            zputa.c
// Created:         January 2019
// Author(s):       Philip Smart
// Description:     ZPU test application.
//                  This program implements tools, test mechanisms and performance analysers such that
//                  a ZPU cpu and the encapsulating SoC can be tested, debugged, validated and rated in
//                  terms of performance.
//
// Credits:         
// Copyright:       (c) 2019 Philip Smart <philip.smart@net2net.org>
//                  (c) 2013, ChaN, framework for the SD Card testing.
//
// History:         January 2019   - Initial script written for the STORM processor then changed to the ZPU.
//                  July 2019      - Addition of the Dhrystone and CoreMark tests.
//
// Notes:           See Makefile to enable/disable conditional components
//                  USELOADB              - The Byte write command is implemented in hw/sw so use it.
//                  USE_BOOT_ROM          - The target is ROM so dont use initialised data.
//                  MINIMUM_FUNTIONALITY  - Minimise functionality to limit code size.
//                  COREMARK_TEST         - Add the CoreMark test suite.
//                  DHYRSTONE_TEST        - Add the Dhrystone test suite.
//                  USE_SDCARD            - Add the SDCard logic.
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
#include "uart.h"
#include "interrupts.h"
#include "ff.h"            /* Declarations of FatFs API */
#include "diskio.h"
#include <zstdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>
#include "xprintf.h"
#ifdef COREMARK_TEST
#include "coremark.h"
#endif
#include "utils.h"
#include "zputa_app.h"     /* Header for definitions specific to apps run from zputa */
#include "zputa.h"

// Version info.
#define VERSION      "v1.3"
#define VERSION_DATE "18/07/2019"
#define PROGRAM_NAME "ZPUTA"

// Utility functions.
#include "tools.c"

// Method to process interrupts. This involves reading the interrupt status register and then calling
// the handlers for each triggered interrupt. A read of the interrupt controller clears the interrupt pending
// register so new interrupts will be processed after this method exits.
//
void interrupt_handler()
{
    // Read the interrupt controller to find which devices caused an interrupt.
    //
    uint32_t intr = INTERRUPT_STATUS(INTR0);

    // Prevent additional interrupts.
    DisableInterrupts();

    dbg_puts("ZPUTA Interrupt Handler\n");

    if(INTR_IS_TIMER(intr))
    {
        dbg_puts("Timer interrupt\n");
    }
    if(INTR_IS_PS2(intr))
    {
        dbg_puts("PS2 interrupt\n");
    }
    if(INTR_IS_IOCTL_RD(intr))
    {
        dbg_puts("IOCTL RD interrupt\n");
    }
    if(INTR_IS_IOCTL_WR(intr))
    {
        dbg_puts("IOCTL WR interrupt\n");
    }
    if(INTR_IS_UART0_RX(intr))
    {
        dbg_puts("UART0 RX interrupt\n");
    }
    if(INTR_IS_UART0_TX(intr))
    {
        dbg_puts("UART0 TX interrupt\n");
    }
    if(INTR_IS_UART1_RX(intr))
    {
        dbg_puts("UART1 RX interrupt\n");
    }
    if(INTR_IS_UART1_TX(intr))
    {
        dbg_puts("UART1 TX interrupt\n");
    }

    // Enable new interrupts.
    EnableInterrupts();
}

// Method to initialise the timer.
//
void initTimer()
{
    dbg_puts("Setting up timer...\n");
    TIMER_INDEX(TIMER1) = 0;                // Set first timer
    TIMER_COUNTER(TIMER1) = 100000;         // Timer is prescaled to 100KHz
}

// Method to enable the timer.
//
void enableTimer()
{
    dbg_puts("Enabling timer...\n");
    TIMER_ENABLE(TIMER1) = 1;               // Enable timer 0
}

// Method to decode a command into a key which is used to select the associated command logic.
//
int16_t decodeCommand(char **ptr)
{
    uint8_t idx;
    char *spaceptr = (*ptr);

    // If no command entered, exit.
    if(*ptr == 0x0)
        return CMD_NOKEY;

    // Find the end of the command and terminate it for comparison.
    while(*spaceptr != ' ' && *spaceptr != 0x00) spaceptr++;
    if(*spaceptr == ' ') { (*spaceptr) = 0x00; spaceptr++; }

    // Loop through all the commands and try to find a match.
    for (idx=0; idx < NCMDKEYS; idx++)
    {
        t_cmdstruct *sym = &cmdTable[idx];
        if (strcmp(sym->cmd, *ptr) == 0 && sym->builtin == 1)
        {
            (*ptr) = spaceptr;
            return sym->key;
        }
    }

    // No command found, so raise error.
    return CMD_BADKEY;
}

// Interactive command processor. Allow user to input a command and execute accordingly.
//
int cmdProcessor(void)
{
    // Local variables.
    char              *ptr;
    char              *ptr2;
    char              *src1FileName;
    char              *src2FileName;
    char              *dstFileName;
    char              line[120];
    uint8_t           diskInitialised = 0;
    uint8_t           fsInitialised = 0;
    long              p1;
    long              p2;
    long              p3;
    uint32_t          up1;
    uint32_t          up2;
    uint32_t          startPos;
    uint32_t          memAddr;
    uint32_t          execAddr;
    uint32_t          len;
    uint32_t          mode;
    uint32_t          width;
    uint32_t          sizeToRead;
    uint32_t          retCode;
    FRESULT           fr;
    BYTE              b1;
    RTC               rtc;
    #if defined(BUILTIN_FS_CHANGETIME) && BUILTIN_FS_CHANGETIME == 1
    FILINFO           Finfo;
    #endif

    // Initialise any globals in the structure used to pass working variables to apps.
    G.Sector = 0;

    // Initialise the first disk if FS enabled as external commands depend on it.
    #if defined(USE_SDCARD)
    fr = FR_NOT_ENABLED;
    if(!disk_initialize(0, 1))
    {
        xsprintf(line, "0:");
        fr = f_mount(&G.FatFs[0], line, 0);
    }

    if(fr)
    {
        xprintf("Failed to initialise sd card 0, please init manually.\n");
    } else
    {
        diskInitialised = 1;
        fsInitialised = 1;
    }
    #endif

    while(1)
    {
        // Prompt to indicate input required.
        xputs("* ");
        ptr = line;
        memset(line, 0x00, sizeof(line));
        xgets(ptr, sizeof(line));

        // main functions
        switch(decodeCommand(&ptr))
        {
        #if defined(USE_SDCARD)
            // DISK commands
          #if defined(BUILTIN_DISK_DUMP) && BUILTIN_DISK_DUMP == 1
            // CMD_DISK_DUMP <pd#> [<sector>] - Dump sector
            case CMD_DISK_DUMP:
                if (!xatoi(&ptr, &p1)) break;
                if (!xatoi(&ptr, &p2)) p2 = G.Sector;
                b1 = disk_read((BYTE)p1, G.Buff, p2, 1);
                if (b1) { xprintf("rc=%d\n", b1); break; }
                G.Sector = p2 + 1;
                xprintf("Sector:%lu\n", p2);
                memoryDump((uint32_t)G.Buff, 0x200, 16, 0, 32);
                break;
          #endif

            // CMD_DISK_INIT <pd#> <card type> - Initialize disk
            case CMD_DISK_INIT:
                if(!xatoi(&ptr, &p1)) { xprintf("Bad disk id!\n"); break; }
                if(xatoi(&ptr, &p2))
                   if(p2 > 1) p2 = 0;
                if(!disk_initialize((BYTE)p1, (BYTE)p2))
                {
                    xputs("Initialised.\n");
                    diskInitialised = 1;
                } else
                    xputs("Failed to initialise.\n");
                break;

          #if defined(BUILTIN_DISK_STATUS) && BUILTIN_DISK_STATUS == 1
            // CMD_DISK_STATUS <pd#> - Show disk status
            case CMD_DISK_STATUS:
                if (!xatoi(&ptr, &p1)) break;
                if (disk_ioctl((BYTE)p1, GET_SECTOR_COUNT, &p2) == RES_OK)
                    { xprintf("Drive size: %lu sectors\n", p2); }
                if (disk_ioctl((BYTE)p1, GET_BLOCK_SIZE, &p2) == RES_OK)
                    { xprintf("Erase block: %lu sectors\n", p2); }
                if (disk_ioctl((BYTE)p1, MMC_GET_TYPE, &b1) == RES_OK)
                    { xprintf("Card type: %u\n", b1); }
                if (disk_ioctl((BYTE)p1, MMC_GET_CSD, G.Buff) == RES_OK)
                    { xputs("CSD:\n"); memoryDump((uint32_t)G.Buff, 16, 16, 0, 32); }
                if (disk_ioctl((BYTE)p1, MMC_GET_CID, G.Buff) == RES_OK)
                    { xputs("CID:\n"); memoryDump((uint32_t)G.Buff, 16, 16, 0, 32); }
                if (disk_ioctl((BYTE)p1, MMC_GET_OCR, G.Buff) == RES_OK)
                    { xputs("OCR:\n"); memoryDump((uint32_t)G.Buff, 4, 16, 0, 32); }
                if (disk_ioctl((BYTE)p1, MMC_GET_SDSTAT, G.Buff) == RES_OK) {
                    xputs("SD Status:\n");
                    memoryDump((uint32_t)G.Buff, 64, 16, 0, 32);
                }
                if (disk_ioctl((BYTE)p1, ATA_GET_MODEL, line) == RES_OK)
                    { line[40] = '\0'; xprintf("Model: %s\n", line); }
                if (disk_ioctl((BYTE)p1, ATA_GET_SN, line) == RES_OK)
                    { line[20] = '\0'; xprintf("S/N: %s\n", line); }
                break;
          #endif

            // CMD_DISK_IOCTL_SYNC <pd#> - CTRL_SYNC
            case CMD_DISK_IOCTL_SYNC:
                if (!xatoi(&ptr, &p1)) break;
                xprintf("rc=%d\n", disk_ioctl((BYTE)p1, CTRL_SYNC, 0));
                break;
    
            // BUFFER commands
          #if defined(BUILTIN_BUFFER_DUMP) && BUILTIN_BUFFER_DUMP == 1
            // CMD_BUFFER_DUMP <offset> - Dump R/W buffer
            case CMD_BUFFER_DUMP:
                if (!xatoi(&ptr, &p1)) break;
                memoryDump((uint32_t)&G.Buff[p1], 0x200, 16, p1, 32);
                break;
          #endif

            // CMD_BUFFER_EDIT <addr> [<data>] ... - Edit R/W buffer
          #if defined(BUILTIN_BUFFER_EDIT) && BUILTIN_BUFFER_EDIT == 1
            case CMD_BUFFER_EDIT:
                if (!xatoi(&ptr, &p1)) break;
                if (xatoi(&ptr, &p2)) {
                    do {
                        G.Buff[p1++] = (BYTE)p2;
                    } while (xatoi(&ptr, &p2));
                    break;
                }
                for (;;) {
                    xprintf("%04X %02X-", (WORD)p1, G.Buff[p1]);
                    xgets(line, sizeof line);
                    ptr = line;
                    if (*ptr == '.') break;
                    if (*ptr < ' ') { p1++; continue; }
                    if (xatoi(&ptr, &p2)) {
                        G.Buff[p1++] = (BYTE)p2;
                    } else {
                        xputs("???\n");
                    }
                }
                break;
          #endif

          #if defined(BUILTIN_BUFFER_READ) && BUILTIN_BUFFER_READ == 1
            // CMD_BUFFER_READ <pd#> <sector> [<n>] - Read disk into R/W buffer
            case CMD_BUFFER_READ:
                if(xatoi(&ptr, &p1))
                   if(xatoi(&ptr, &p2))
                   {
                       if(!xatoi(&ptr, &p3)) p3 = 1;
                       xprintf("rc=%u\n", disk_read((BYTE)p1, G.Buff, p2, p3));
                   }
                break;
          #endif

          #if defined(BUILTIN_BUFFER_WRITE) && BUILTIN_BUFFER_WRITE == 1
            // CMD_BUFFER_WRITE <pd#> <sector> [<n>] - Write R/W buffer into disk
            case CMD_BUFFER_WRITE:
                if(xatoi(&ptr, &p1))
                   if(xatoi(&ptr, &p2))
                   {
                       if (!xatoi(&ptr, &p3)) p3 = 1;
                       xprintf("rc=%u\n", disk_write((BYTE)p1, G.Buff, p2, p3));
                   }
                break;
          #endif

          #if defined(BUILTIN_BUFFER_FILL) && BUILTIN_BUFFER_FILL == 1
            // CMD_BUFFER_FILL <n> - Fill working buffer
            case CMD_BUFFER_FILL:
                if (!xatoi(&ptr, &p1)) break;
                memset(G.Buff, (BYTE)p1, sizeof G.Buff);
                break;
          #endif

          #if defined(BUILTIN_BUFFER_LEN) && BUILTIN_BUFFER_LEN == 1
            // CMD_BUFFER_LEN <len> - Set read/write size for fr/fw command
            case CMD_BUFFER_LEN:
                len = getUintParam(&ptr);
                fr  = fileSetBlockLen(len);
                if (fr) { printFSCode(fr); break; }
                xprintf("R/W length = %u\n", len);
                break;
          #endif
    
            // FILESYSTEM commands.
            // CMD_FS_INIT <ld#> [<mount>]- Initialize logical drive
            case CMD_FS_INIT:
                if(xatoi(&ptr, &p1))
                   if((UINT)p1 > 9) break;
                if(!xatoi(&ptr, &p2)) p2 = 0;
                xsprintf(line, "%u:", (UINT)p1);
                fr = f_mount(&G.FatFs[p1], line, (BYTE)p2);
                if(fr)
                    printFSCode(fr);
                else
                {
                    xputs("Initialised.\n");
                    fsInitialised = 1;
                }
                break;
        
            // CMD_FS_STATUS [<path>] - Show logical drive status
          #if defined(BUILTIN_FS_STATUS) && BUILTIN_FS_STATUS == 1
            case CMD_FS_STATUS:
                fr = printFatFSStatus(getStrParam(&ptr));
                if (fr) { printFSCode(fr); break; }
                break;
          #endif
        
            // CMD_FS_DIRLIST [<path>] - Directory listing
          #if defined(BUILTIN_FS_DIRLIST) && BUILTIN_FS_DIRLIST == 1
            case CMD_FS_DIRLIST:
                fr = printDirectoryListing(getStrParam(&ptr));
                if (fr) { printFSCode(fr); break; }
                break;
          #endif
        
            // CMD_FS_OPEN <mode> <name> - Open a file
          #if defined(BUILTIN_FS_OPEN) && BUILTIN_FS_OPEN == 1
            case CMD_FS_OPEN:
                if(G.fileInUse) { xputs("File already open, please close before re-opening\n"); break; }
                if (!xatoi(&ptr, &p1)) break;
                while (*ptr == ' ') ptr++;
                fr = f_open(&G.File[0], ptr, (BYTE)p1);
                printFSCode(fr);
                if( fr == FR_OK ) { G.fileInUse = 1; }
                break;
          #endif
        
            // CMD_FS_CLOSE - Close a file
          #if defined(BUILTIN_FS_CLOSE) && BUILTIN_FS_CLOSE == 1
            case CMD_FS_CLOSE:
                if(G.fileInUse == 0) { xputs("No file open, cannot close.\n"); break; }
                fr=f_close(&G.File[0]);
                printFSCode(fr);
                if(fr == FR_OK) { G.fileInUse = 0; }
                break;
          #endif
        
            // CMD_FS_SEEK - Seek file pointer
          #if defined(BUILTIN_FS_READ) && BUILTIN_FS_READ == 1
            case CMD_FS_SEEK:
                if(G.fileInUse == 0) { xputs("No file open, cannot seek.\n"); break; }
                if (!xatoi(&ptr, &p1)) break;
                fr = f_lseek(&G.File[0], p1);
                printFSCode(fr);
                if (fr == FR_OK) {
                    xprintf("fptr = %lu(0x%lX)\n", (DWORD)G.File[0].fptr, (DWORD)G.File[0].fptr);
                }
                break;
          #endif
        
            // CMD_FS_READ <len> - read file
          #if defined(BUILTIN_FS_READ) && BUILTIN_FS_READ == 1
            case CMD_FS_READ:
                if(G.fileInUse == 0) { xputs("No file open, cannot read.\n"); break; }
                fr = fileBlockRead(&G.File[0], getUintParam(&ptr));
                if(fr) { printFSCode(fr); } 
                break;
          #endif

            // CMD_FS_CAT <name> - cat/output file
          #if defined(BUILTIN_FS_CAT) && BUILTIN_FS_CAT == 1
            case CMD_FS_CAT:
                fr = fileCat(getStrParam(&ptr));
                if(fr) { printFSCode(fr); } 
                break;
          #endif

            // CMD_FS_LOAD <name> <addr> - Load a file into memory
          #if defined(BUILTIN_FS_LOAD) && BUILTIN_FS_LOAD == 1
            case CMD_FS_LOAD:
                src1FileName = getStrParam(&ptr);
                memAddr = getUintParam(&ptr);
                fr = fileLoad(src1FileName, memAddr, 1);
                if(fr) { printFSCode(fr); } 
                break;
          #endif
                
            // CMD_FS_SAVE <name> <addr> <len> - Save memory range into a file.
          #if defined(BUILTIN_FS_SAVE) && BUILTIN_FS_SAVE == 1
            case CMD_FS_SAVE:
                dstFileName = getStrParam(&ptr);
                memAddr     = getUintParam(&ptr);
                len         = getUintParam(&ptr);
                fr = fileSave(dstFileName, memAddr, len);
                if(fr) { printFSCode(fr); } 
                break;
          #endif
               
            // CMD_FS_EXEC <name> <loadAddr> <execAddr> <mode> - Load a file into memory and exeute.
          #if defined(BUILTIN_FS_EXEC) && BUILTIN_FS_EXEC == 1
            case CMD_FS_EXEC:
                src1FileName = getStrParam(&ptr);
                memAddr      = getUintParam(&ptr);
                execAddr     = getUintParam(&ptr);
                mode         = getUintParam(&ptr);
                fr = fileExec(src1FileName, memAddr, execAddr, mode, 0, 0, (uint32_t)&G, (uint32_t)&cfgSoC);
                if(fr) { printFSCode(fr); } 
                break;
          #endif

            // CMD_FS_DUMP <name> [<width>] - Dump a file contents as hex
          #if defined(BUILTIN_FS_DUMP) && BUILTIN_FS_DUMP == 1
            case CMD_FS_DUMP:
                src1FileName = getStrParam(&ptr);
                if((width = getUintParam(&ptr)) == 0) { width = 8; }
                fr = fileDump(src1FileName, width);
                if(fr) { printFSCode(fr); } 
                break;
          #endif

            // CMD_FS_INSPECT <offset> [<len>] - read and dump file from current fp
          #if defined(BUILTIN_FS_INSPECT) && BUILTIN_FS_INSPECT == 1
            case CMD_FS_INSPECT:
                if(G.fileInUse == 0) { xputs("No file open, buffer contents invalid.\n"); break; }
                startPos    = getUintParam(&ptr);
                len         = getUintParam(&ptr);
                fr = fileBlockDump(startPos, len);
                if(fr) { printFSCode(fr); } 
                break;
          #endif

            // fw <len> - write buffer to file
          #if defined(BUILTIN_FS_WRITE) && BUILTIN_FS_WRITE == 1
            case CMD_FS_WRITE:
                if(G.fileInUse == 0) { xputs("No file open, cannot write.\n"); break; }
                fr = fileBlockWrite(&G.File[0], getUintParam(&ptr));
                if(fr) { printFSCode(fr); } 
                break;
          #endif
    
            // CMD_FS_TRUNC - Truncate file
          #if defined(BUILTIN_FS_TRUNC) && BUILTIN_FS_TRUNC == 1
            case CMD_FS_TRUNC:
                if(G.fileInUse == 0) { xputs("No file open, cannot truncate.\n"); break; }
                printFSCode(f_truncate(&G.File[0]));
                break;
          #endif
    
            // CMD_FS_RENAME <old_name> <new_name> - Change file/dir name
          #if defined(BUILTIN_FS_RENAME) && BUILTIN_FS_RENAME == 1
            case CMD_FS_RENAME:
                ptr2 = strchr(ptr, ' ');
                if (!ptr2) break;
                *ptr2++ = 0;
                while (*ptr2 == ' ') ptr2++;
                printFSCode(f_rename(ptr, ptr2));
                break;
          #endif
        
            // CMD_FS_DELETE <name> - Delete a file or dir
          #if defined(BUILTIN_FS_DELETE) && BUILTIN_FS_DELETE == 1
            case CMD_FS_DELETE:
                printFSCode(f_unlink(ptr));
                break;
          #endif
        
            // CMD_FS_CREATEDIR <name> - Create a directory
          #if defined(BUILTIN_FS_CREATEDIR) && BUILTIN_FS_CREATEDIR == 1
            case CMD_FS_CREATEDIR:
                printFSCode(f_mkdir(ptr));
                break;
          #endif

          #if defined(BUILTIN_FS_ALLOCBLOCK) && BUILTIN_FS_ALLOCBLOCK == 1
            #if FF_USE_EXPAND
            // CMD_FS_ALLOCBLOCK <fsz> <opt> - Allocate contiguous block
            case CMD_FS_ALLOCBLOCK:
                if(G.fileInUse == 0) { xputs("No file open, cannot allocate block.\n"); break; }
                if (!xatoi(&ptr, &p1) || !xatoi(&ptr, &p2)) break;
                fr = f_expand(&G.File[0], (DWORD)p1, (BYTE)p2);
                printFSCode(fr);
                break;
            #endif
          #endif
          #if FF_USE_CHMOD
            #if defined(BUILTIN_FS_CHANGEATTRIB) && BUILTIN_FS_CHANGEATTRIB == 1
            // CMD_FS_CHANGEATTRIB <atrr> <mask> <name> - Change file/dir attribute
            case CMD_FS_CHANGEATTRIB:
                if (!xatoi(&ptr, &p1) || !xatoi(&ptr, &p2)) break;
                while (*ptr == ' ') ptr++;
                printFSCode(f_chmod(ptr, p1, p2));
                break;
            #endif
        
            // CMD_FS_CHANGETIME <year> <month> <day> <hour> <min> <sec> <name>
            #if defined(BUILTIN_FS_CHANGETIME) && BUILTIN_FS_CHANGETIME == 1
            case CMD_FS_CHANGETIME:
                if (!xatoi(&ptr, &p1) || !xatoi(&ptr, &p2) || !xatoi(&ptr, &p3)) break;
                Finfo.fdate = ((p1 - 1980) << 9) | ((p2 & 15) << 5) | (p3 & 31);
                if (!xatoi(&ptr, &p1) || !xatoi(&ptr, &p2) || !xatoi(&ptr, &p3)) break;
                Finfo.ftime = ((p1 & 31) << 11) | ((p2 & 63) << 5) | ((p3 >> 1) & 31);
                while (*ptr == ' ') ptr++;
                printFSCode(f_utime(ptr, &Finfo));
                break;
            #endif
          #endif

            // CMD_FS_COPY <src_name> <dst_name> - Copy file
          #if defined(BUILTIN_FS_COPY) && BUILTIN_FS_COPY == 1
            case CMD_FS_COPY:
                src1FileName=getStrParam(&ptr);
                dstFileName=getStrParam(&ptr);
                fr = fileCopy(src1FileName, dstFileName);
                if(fr) { printFSCode(fr); } 
                break;
          #endif

            // CMD_FS_CONCAT <src_name_1> <src_name_2> <dst_file>
          #if defined(BUILTIN_FS_CONCAT) && BUILTIN_FS_CONCAT == 1
            case CMD_FS_CONCAT:
                src1FileName=getStrParam(&ptr);
                src2FileName=getStrParam(&ptr);
                dstFileName=getStrParam(&ptr);
                fr = fileConcatenate(src1FileName, src2FileName, dstFileName);
                if(fr) { printFSCode(fr); } 
                break;
          #endif
 
            // CMD_FS_XTRACT <src_name> <dst_file> <start pos> <len>
          #if defined(BUILTIN_FS_XTRACT) && BUILTIN_FS_XTRACT == 1
            case CMD_FS_XTRACT:
                src1FileName= getStrParam(&ptr);
                dstFileName = getStrParam(&ptr);
                startPos    = getUintParam(&ptr);
                len         = getUintParam(&ptr);
                fr = fileXtract(src1FileName, dstFileName, startPos, len);
                if(fr) { printFSCode(fr); } 
                break;
          #endif

          #if FF_FS_RPATH
            #if defined(BUILTIN_FS_CHANGEDIR) && BUILTIN_FS_CHANGEDIR == 1
            // CMD_FS_CHANGEDIR <path> - Change current directory
            case CMD_FS_CHANGEDIR:
                printFSCode(f_chdir(ptr));
                break;
            #endif
           #if FF_VOLUMES >= 2
            // CMD_FS_CHANGEDRIVE <path> - Change current drive
            #if defined(BUILTIN_FS_CHANGEDRIVE) && BUILTIN_FS_CHANGEDRIVE == 1
            case CMD_FS_CHANGEDRIVE:
                printFSCode(f_chdrive(ptr));
                break;
            #endif
           #endif
           #if FF_FS_RPATH >= 2
            // CMD_FS_SHOWDIR - Show current dir path
            #if defined(BUILTIN_FS_SHOWDIR) && BUILTIN_FS_SHOWDIR == 1
            case CMD_FS_SHOWDIR:
                fr = f_getcwd(line, sizeof line);
                if (fr) {
                    printFSCode(fr);
                } else {
                    xprintf("%s\n", line);
                }
                break;
            #endif
           #endif
          #endif
          #if FF_USE_LABEL
            // CMD_FS_SETLABEL <name> - Set volume label
            #if defined(BUILTIN_FS_SETLABEL) && BUILTIN_FS_SETLABEL == 1
            case CMD_FS_SETLABEL:
                printFSCode(f_setlabel(ptr));
                break;
            #endif
          #endif
          #if FF_USE_MKFS
            // CMD_FS_CREATEFS <ld#> <type> <bytes/clust> - Create filesystem
            #if defined(BUILTIN_FS_CREATEFS) && BUILTIN_FS_CREATEFS == 1
            case CMD_FS_CREATEFS:
                if (!xatoi(&ptr, &p1) || (UINT)p1 > 9 || !xatoi(&ptr, &p2) || !xatoi(&ptr, &p3)) break;
                xprintf("The drive %u will be formatted. Are you sure? (Y/n)=", (WORD)p1);
                xgets(line, sizeof line);
                if (line[0] == 'Y') {
                    xsprintf(line, "%u:", (UINT)p1);
                    printFSCode(f_mkfs(line, (BYTE)p2, (DWORD)p3, G.Buff, sizeof G.Buff));
                }
                break;
            #endif
          #endif
        #endif  // USE_SDCARD

          #if defined(BUILTIN_MISC_SETTIME) && BUILTIN_MISC_SETTIME == 1
            // CMD_MISC_SETTIME [<year> <mon> <day> <hour> <min> <sec>]
            case CMD_MISC_SETTIME:
                if (xatoi(&ptr, &p1)) {
                    rtc.year = (uint16_t)p1;
                    xatoi(&ptr, &p1); rtc.month = (uint8_t)p1;
                    xatoi(&ptr, &p1); rtc.day = (uint8_t)p1;
                    xatoi(&ptr, &p1); rtc.hour = (uint8_t)p1;
                    xatoi(&ptr, &p1); rtc.min = (uint8_t)p1;
                    if (!xatoi(&ptr, &p1)) break;
                    rtc.sec = (uint8_t)p1;
                    rtc.msec = 0;
                    rtc.usec = 0;
                    rtcSet(&rtc);
                }

                rtcGet(&rtc);
                xprintf("%u/%u/%u %02u:%02u:%02u.%03u%03u\n", rtc.year, rtc.month, rtc.day, rtc.hour, rtc.min, rtc.sec, rtc.msec, rtc.usec);
                break;
          #endif
    
            // MEMORY commands
            //
          #if defined(BUILTIN_MEM_CLEAR) && BUILTIN_MEM_CLEAR == 1
            // Clear memory <start addr> <end addr> [<word>]
            case CMD_MEM_CLEAR:
                if (!xatoi(&ptr, &p1)) break;
                if (!xatoi(&ptr, &p2)) break;
                if (!xatoi(&ptr, &p3))
                {
                    p3 = 0x00000000;
                }
                xputs("Clearing...");
                for(memAddr=p1; memAddr < p2; memAddr+=4)
                {
                    *(uint32_t *)(memAddr) = p3;
                }
                xputs("\n");
                break;
          #endif

          #if defined(BUILTIN_MEM_COPY) && BUILTIN_MEM_COPY == 1
            // Copy memory <start addr> <end addr> <dst addr>
            case CMD_MEM_COPY:
                if (!xatoi(&ptr, &p1)) break;
                if (!xatoi(&ptr, &p2)) break;
                if (!xatoi(&ptr, &p3)) break;
                xputs("Copying...");
                for(memAddr=p1; memAddr < p2; memAddr++, p3++)
                {
                    *(uint8_t *)(p3) = *(uint8_t *)(memAddr);
                }
                xputs("\n");
                break;
          #endif

          #if defined(BUILTIN_MEM_DIFF) && BUILTIN_MEM_DIFF == 1
            // Compare memory <start addr> <end addr> <compare addr>
            case CMD_MEM_DIFF:
                if (!xatoi(&ptr, &p1)) break;
                if (!xatoi(&ptr, &p2)) break;
                if (!xatoi(&ptr, &p3)) break;
                xputs("Comparing...");
                for(memAddr=p1; memAddr < p2; memAddr++, p3++)
                {
                    if(*(uint8_t *)(p3) != *(uint8_t *)(memAddr))
                    {
                        xprintf("%08lx(%08x)->%08lx(%08x)\n", memAddr, *(uint8_t *)(memAddr), p3, *(uint8_t *)(p3));
                    }
                }
                xputs("\n");
                break;
          #endif

          #if defined(BUILTIN_MEM_DUMP) && BUILTIN_MEM_DUMP == 1
            // Dump memory, [<start addr>, [<end addr>], [<size>]]
            case CMD_MEM_DUMP:
                if (!xatoi(&ptr, &p1))
                {
                    if(cfgSoC.implInsnBRAM)  { p1 = cfgSoC.addrInsnBRAM; }
                    else if(cfgSoC.implBRAM) { p1 = cfgSoC.addrBRAM; }
                    else if(cfgSoC.implRAM || cfgSoC.implDRAM) { p1 = cfgSoC.addrRAM; }
                    else { p1 = cfgSoC.stackStartAddr - 512; }
                }
                if (!xatoi(&ptr,  &p2))
                {
                    if(cfgSoC.implInsnBRAM)  { p2 = cfgSoC.sizeInsnBRAM; }
                    else if(cfgSoC.implBRAM) { p2 = cfgSoC.sizeBRAM; }
                    else if(cfgSoC.implRAM || cfgSoC.implDRAM) { p2 = cfgSoC.sizeRAM; }
                    else { p2 = cfgSoC.stackStartAddr + 8; }
                }
                if (!xatoi(&ptr,  &p3) || (p3 != 8 && p3 != 16 && p3 != 32))
                {
                    p3 = 8;
                }
                xputs("Dump Memory\n");
                memoryDump(p1, p2, p3, p1, 32);
                xputs("\nComplete.\n");
                break;
          #endif

          #if defined(BUILTIN_MEM_EDIT_BYTES) && BUILTIN_MEM_EDIT_BYTES == 1
            // Edit memory with bytes, <addr> <byte> [<byte> .... <byte>]
            case CMD_MEM_EDIT_BYTES:
                if (!xatoi(&ptr, &p1)) break;
                if (xatoi(&ptr, &p2))
                {
                    do {
                        *(uint8_t *)(p1++) = (uint8_t)p2;
                    } while (xatoi(&ptr, &p2));
                    break;
                }
                for (;;)
                {
                    xprintf("%08X %02X-", (uint32_t)p1, *(uint8_t *)p1);
                    xgets(line, sizeof line);
                    ptr = line;
                    if (*ptr == '.') break;
                    if (*ptr < ' ') { p1++; continue; }
                    if (xatoi(&ptr, &p2))
                    {
                        *(uint8_t *)(p1++) = (uint8_t)p2;
                    } else {
                        xputs("???\n");
                    }
                }
                break;
          #endif
                            
          #if defined(BUILTIN_MEM_EDIT_HWORD) && BUILTIN_MEM_EDIT_HWORD == 1
            // Edit memory with half-words, <addr> <16bit h-word> [<h-word> .... <h-word>]
            case CMD_MEM_EDIT_HWORD:
                if (!uxatoi(&ptr, &up1)) break;
                if (uxatoi(&ptr, &up2))
                {
                    do {
                        *(uint16_t *)(up1) = (uint16_t)up2;
                        up1 += 2;
                    } while (uxatoi(&ptr, &up2));
                    break;
                }
                for (;;)
                {
                    xprintf("%08X %04X-", (uint32_t)up1, *(uint16_t *)up1);
                    xgets(line, sizeof line);
                    ptr = line;
                    if (*ptr == '.') break;
                    if (*ptr < ' ') { up1 += 4; continue; }
                    if (uxatoi(&ptr, &up2))
                    {
                        *(uint16_t *)(up1) = (uint16_t)up2;
                        up1 += 2;
                    } else {
                        xputs("???\n");
                    }
                }
                break;
          #endif
                        
          #if defined(BUILTIN_MEM_EDIT_WORD) && BUILTIN_MEM_EDIT_WORD == 1
            // Edit memory with words, <addr> <word> [<word> .... <word>]
            case CMD_MEM_EDIT_WORD:
                if (!uxatoi(&ptr, &up1)) break;
                if (uxatoi(&ptr, &up2))
                {
                    do {
                        *(uint32_t *)(up1) = up2;
                        up1 += 4;
                    } while (uxatoi(&ptr, &up2));
                    break;
                }
                for (;;)
                {
                    xprintf("%08X %08X-", up1, *(uint32_t *)(up1));
                    xgets(line, sizeof line);
                    ptr = line;
                    if (*ptr == '.') break;
                    if (*ptr < ' ') { up1 += 4; continue; }
                    if (uxatoi(&ptr, &up2))
                    {
                        xprintf("%08X %08X-", up1, up2);
                        *(uint32_t *)(up1) = up2;
                        up1 += 4;
                    } else {
                        xputs("???\n");
                    }
                }
                break;
          #endif

            // HARDWARE commands
            //
            // Disable interrupts
            case CMD_HW_INTR_DISABLE:
                xputs("Disabling interrupts\n");
                DisableInterrupt(INTR_TIMER);
                break;
        
            // Enable interrupts
            case CMD_HW_INTR_ENABLE:
                xputs("Enabling interrupts\n");
                //EnableInterrupt(INTR_TIMER | INTR_PS2 | INTR_IOCTL_RD | INTR_IOCTL_WR | INTR_UART0_RX | INTR_UART0_TX | INTR_UART1_RX | INTR_UART1_TX);
                EnableInterrupt(INTR_TIMER | INTR_UART0_RX);
                break;

          #if defined(BUILTIN_HW_SHOW_REGISTER) && BUILTIN_HW_SHOW_REGISTER == 1
            // Output register Information.
            case CMD_HW_SHOW_REGISTER:
                xputs("Register information\n");
                xputs("Interrupt: ");
                xprintf("%08X %08X\n", INTERRUPT_STATUS(INTR0), INTERRUPT_CTRL(INTR0));
                while(getserial_nonblocking() == -1)
                {
                    xprintf("UART 0/1: %08X %08X %08X %08X %08X %08X\r", UART_STATUS(UART0), UART_FIFO_STATUS(UART0), UART_BRGEN(UART0), UART_STATUS(UART1), UART_FIFO_STATUS(UART1), UART_BRGEN(UART1));
                    memAddr = INTERRUPT_STATUS(INTR0);
                }
                xputs("\n");
                break;
          #endif
        
          #if defined(BUILTIN_HW_TEST_TIMERS) && BUILTIN_HW_TEST_TIMERS == 1
            // Output RTC and test timer up/down counters.
            case CMD_HW_TEST_TIMERS:
                xputs("Testing RTC & Up/Down Timers\n");
                TIMER_MILLISECONDS_UP = 60000;
                while(getserial_nonblocking() == -1)
                {
                    if(TIMER_MICROSECONDS_DOWN == 0)
                    {
                        TIMER_MICROSECONDS_DOWN = 10000000;
                        xputs("\r\nuSec down counter expired.\n");
                    }
                    if(TIMER_MILLISECONDS_DOWN == 0)
                    {
                        TIMER_MILLISECONDS_DOWN = 60000;
                        xputs("\r\nmSec down counter expired.\n");
                    }
                    if(TIMER_SECONDS_DOWN == 0)
                    {
                        TIMER_SECONDS_DOWN = 60;
                        xputs("\r\nSecond down counter expired.\n");
                    }
                    if(TIMER_MILLISECONDS_UP == 60000)
                    {
                        TIMER_MILLISECONDS_UP = 0;
                        xputs("\r\nmSec up counter expired.\n");
                    }

                    xprintf("%02d/%02d/%02d %02d:%02d:%02d.%03d%03d %10lu %10lu %10lu %10lu\r", RTC_YEAR, RTC_MONTH, RTC_DAY, RTC_HOUR, RTC_MINUTE, RTC_SECOND, RTC_MILLISECONDS, RTC_MICROSECONDS, TIMER_MICROSECONDS_DOWN, TIMER_MILLISECONDS_DOWN, TIMER_SECONDS_DOWN, TIMER_MILLISECONDS_UP);
                }
                xputs("\n");
                break;
          #endif
        
            // Disable UART fifo
            case CMD_HW_FIFO_DISABLE:
                UART_CTRL(UART0)  = UART_TX_ENABLE | UART_RX_ENABLE;
                UART_CTRL(UART1)  = UART_TX_ENABLE | UART_RX_ENABLE;
                xputs("Disabled uart fifo\n");
                break;
                                
            // Enable UART fifo
            case CMD_HW_FIFO_ENABLE:
                xputs("Enabling uart fifo\n");
                UART_CTRL(UART0)  = UART_TX_FIFO_ENABLE | UART_TX_ENABLE | UART_RX_FIFO_ENABLE | UART_RX_ENABLE;
                UART_CTRL(UART1)  = UART_TX_FIFO_ENABLE | UART_TX_ENABLE | UART_RX_FIFO_ENABLE | UART_RX_ENABLE;
                break;

            // TESTING commands
          #if defined(DHRYSTONE_TEST)&& defined(BUILTIN_TST_DHRYSTONE) && BUILTIN_TST_DHRYSTONE == 1
            case CMD_TEST_DHRYSTONE:
                // Run a Dhrystone test to evaluate CPU speed.
                xputs("Running Dhrystone test, please wait ...\n\n");
                main_dhry();
                break;
          #endif

          #if defined(COREMARK_TEST)&& defined(BUILTIN_TST_COREMARK) && BUILTIN_TST_COREMARK == 1
            case CMD_TEST_COREMARK:
                // Run a CoreMark test to evaluate CPU speed.
                xputs("Running CoreMark test, please wait ...\n\n");
                CoreMarkTest();
                break;
          #endif
                
            // EXECUTION commands.
            case CMD_EXECUTE:
                if (!xatoi(&ptr, &p1)) break;
                xprintf("Executing code @ %08x ...\n", p1);
                void *jmpptr = (void *)p1;
                goto *jmpptr;
                break;

            case CMD_CALL:
                if (!xatoi(&ptr, &p1)) break;
                xprintf("Calling code @ %08x ...\n", p1);
                int  (*func)(void) = (int (*)(void))p1;
                int retCode = func();
                if(retCode != 0)
                {
                    xprintf("Call returned code (%d).\n", retCode);
                }
                break;

            // MISC commands
            case CMD_MISC_RESTART_APP:
                xputs("Restarting application...\n");
                _start();
                break;

            // Reboot the ZPU to the cold start location.
            case CMD_MISC_REBOOT:
                xputs("Cold rebooting...\n");
                void *rbtptr = (void *)0x00000000;
                goto *rbtptr;
                break;

            // Help screen
          #if defined(BUILTIN_MISC_HELP) && BUILTIN_MISC_HELP == 1
            case CMD_MISC_HELP:
                displayHelp(ptr);
                break;
          #endif

            // Test screen
            case CMD_MISC_TEST:
                break;

            // Configuration information
            case CMD_MISC_INFO:
                showSoCConfig();
                break;
            
            // Unrecognised command, if SD card enabled, see if the command exists as an app. If it is an app, load and execute
            // otherwise throw error..
            case CMD_BADKEY:
            default:
                if(*ptr != 0x00)
                {
                #if defined(USE_SDCARD)
                    if(diskInitialised && fsInitialised)
                    {
                        // Append the app extension to the command and try to execute.
                        src1FileName=getStrParam(&ptr);
                        xsprintf(&line[40], "%d:\\%s\\%s.%s", APP_CMD_BIN_DRIVE, APP_CMD_BIN_DIR, src1FileName, APP_CMD_EXTENSION);
                        retCode = fileExec(&line[40], APP_CMD_LOAD_ADDR, APP_CMD_EXEC_ADDR, EXEC_MODE_CALL, (uint32_t) ++ptr, 0, (uint32_t)&G, (uint32_t)&cfgSoC);
                    }
                    if(!diskInitialised || !fsInitialised || retCode == 0xffffffff)
                    {
                        xprintf("Bad command.\n");
                    }
                #else
                    xprintf("Unknown command!\n");
                #endif
                }
                break;

            // No input
            case CMD_NOKEY:
                break;
        }
    }
}

int main(int argc, char **argv)
{
    // Initialisation.
    //
    G.fileInUse = 0;

  // When ZPUTA is the booted app or is booted by the tiny IOCP bootstrap, initialise hardware as it hasnt yet been done.
  #if defined(ZPUTA_BASEADDR) && (ZPUTA_BASEADDR == 0x0000 || ZPUTA_BASEADDR == 0x1000)
    // Setup the required baud rate for the UART. Once the divider is loaded, a reset takes place within the UART.
    UART_BRGEN(UART0) = BAUDRATEGEN(115200, 115200);
    UART_BRGEN(UART1) = BAUDRATEGEN(115200, 115200);

    // Enable the RX/TX units and enable FIFO mode.
    UART_CTRL(UART0)  = UART_TX_FIFO_ENABLE | UART_TX_ENABLE | UART_RX_FIFO_ENABLE | UART_RX_ENABLE;
    UART_CTRL(UART1)  = UART_TX_FIFO_ENABLE | UART_TX_ENABLE | UART_RX_FIFO_ENABLE | UART_RX_ENABLE;
  #endif

    // Setup the input/output devices for the xprintf library.
    xdev_out(putchar);
    xdev_in(getserial);  // xdev_in(getserial_nonblocking); // xdev_in(getdbgserial);

    // Setup the configuration using the SoC configuration register if implemented otherwise the compiled internals.
    setupSoCConfig();

    // Ensure interrupts are disabled whilst setting up.
    DisableInterrupts();

    //xputs("Setting up timer...\n");
    //TIMER_INDEX(TIMER1) = 0;                // Set first timer
    //TIMER_COUNTER(TIMER1) = 100000;         // Timer is prescaled to 100KHz
    //enableTimer();

    // Indicate life...
    puts("Running...\n");

    xputs("Enabling interrupts...\n");
    SetIntHandler(interrupt_handler);
    //EnableInterrupt(INTR_TIMER | INTR_PS2 | INTR_IOCTL_RD | INTR_IOCTL_WR | INTR_UART0_RX | INTR_UART0_TX | INTR_UART1_RX | INTR_UART1_TX);
    //EnableInterrupt(INTR_UART0_RX | INTR_UART1_RX); // | INTR_TIMER);

    // Intro screen
    printVersion(true);

    // Command processor. If it exits, then reset the CPU.
    cmdProcessor();

    // Reboot as it is not normal the command processor terminates.
    void *rbtptr = (void *)0x00000000;
    goto *rbtptr;
}
