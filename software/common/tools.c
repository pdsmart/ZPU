////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            tools.c
// Created:         January 2019
// Author(s):       Philip Smart
// Description:     ZPU tools.
//                  A set of tools to be used by ZPUTA application.
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
#if defined(USE_SDCARD)
#include "ff.h"
#endif
#include "utils.h"
#include "tools.h"

#if defined(USE_SDCARD)
// List of known filesystem types.
static const char* const fileSystemTypeTable[] = {"", "FAT12", "FAT16", "FAT32", "exFAT"};

BYTE          fsBuff[SECTOR_SIZE];                               /* File system working buffer */
DWORD         AccSize;
WORD          AccFiles;
WORD          AccDirs;
uint32_t      blockLen = SECTOR_SIZE;

// Function to write out result code after a FatFS call.
//
#if defined(ZPUTA)
void printFSCode(FRESULT result)
{
    switch(result)
    {
        case FR_DISK_ERR:
            xputs("Disk Error\n");
            break;

        case FR_INT_ERR:
            xputs("Internal error.\n");
            break;

        case FR_NOT_READY:
            xputs("Disk not ready.\n");
            break;

        case FR_NO_FILE:
            xputs("No file found.\n");
            break;

        case FR_NO_PATH:
            xputs("No path found.\n");
            break;

        case FR_INVALID_NAME:
            xputs("Invalid filename.\n");
            break;

        case FR_DENIED:
            xputs("Access denied.\n");
            break;

        case FR_EXIST:
            xputs("File already exists.\n");
            break;

        case FR_INVALID_OBJECT:
            xputs("File handle invalid.\n");
            break;

        case FR_WRITE_PROTECTED:
            xputs("SD is write protected.\n");
            break;

        case FR_INVALID_DRIVE:
            xputs("Drive number is invalid.\n");
            break;

        case FR_NOT_ENABLED:
            xputs("Disk not enabled.\n");
            break;

        case FR_NO_FILESYSTEM:
            xputs("No compatible filesystem found on disk.\n");
            break;

        case FR_MKFS_ABORTED:
            xputs("Format aborted.\n");
            break;

        case FR_TIMEOUT:
            xputs("Timeout, operation cancelled.\n");
            break;

        case FR_LOCKED:
            xputs("File is locked.\n");
            break;

        case FR_NOT_ENOUGH_CORE:
            xputs("Insufficient memory.\n");
            break;

        case FR_TOO_MANY_OPEN_FILES:
            xputs("Too many open files.\n");
            break;

        case FR_INVALID_PARAMETER:
            xputs("Parameters incorrect.\n");
            break;

        case FR_OK:
            xputs("Success.\n");
            break;

        default:
            xputs("Unknown error.\n");
            break;
    }
}
#endif

// Method to calculate throughput of an SD transaction and display.
//
void printBytesPerSec(uint32_t bytes, uint32_t mSec, char *action)
{
    uint32_t bytesPerSec;

    if(mSec < 1000)
    {
        bytesPerSec = bytes * 1000 / mSec;
    } else
    {
        bytesPerSec = bytes / (mSec / 1000);
    }
    xprintf("\n%lu bytes %s at %lu bytes/sec.\n", bytes, action, bytesPerSec);
}

// Function to dump out a given section of memory via the UART.
//
#if (defined(BUILTIN_FS_DUMP) && BUILTIN_FS_DUMP == 1) || (defined(BUILTIN_FS_INSPECT) && BUILTIN_FS_INSPECT == 1) || (defined(BUILTIN_DISK_DUMP) && BUILTIN_DISK_DUMP == 1) || (defined(BUILTIN_DISK_STATUS) && BUILTIN_DISK_STATUS == 1) || (defined(BUILTIN_BUFFER_DUMP) && BUILTIN_BUFFER_DUMP == 1) || (defined(BUILTIN_MEM_DUMP) && BUILTIN_MEM_DUMP == 1)
int memoryDump(uint32_t memaddr, uint32_t memsize, uint32_t memwidth, uint32_t dispaddr, uint8_t dispwidth)
{
    uint32_t pnt     = memaddr;
    uint32_t endAddr = memaddr + memsize;
    uint32_t addr    = dispaddr;
    uint32_t i = 0;
    uint32_t data;
    int8_t   keyIn;
    char c = 0;

    while (1)
    {
        xprintf("%08X", addr); // print address
        xputs(":  ");

        // print hexadecimal data
        for (i=0; i < dispwidth; )
        {
            switch(memwidth)
            {
                case 16:
                    if(pnt+i < endAddr)
                        xprintf("%04X", *(uint16_t *)(pnt+i));
                    else
                        xputs("    ");
                        //puts("    ");
                    i+=2;
                    break;

                case 32:
                    if(pnt+i < endAddr)
                        xprintf("%08X", *(uint32_t *)(pnt+i));
                    else
                        xputs("        ");
                    i+=4;
                    break;

                case 8:
                default:
                    if(pnt+i < endAddr)
                        xprintf("%02X", *(uint8_t *)(pnt+i));
                    else
                        xputs("  ");
                    i++;
                    break;
            }
            putchar((char)' ');
        }
 
        // print ascii data
        xputs(" |");

        // print single ascii char
        for (i=0; i < dispwidth; i++)
        {
            c = (char)*(uint8_t *)(pnt+i);
            if ((pnt+i < endAddr) && (c >= ' ') && (c <= '~'))
                putchar((char)c);
            else
                putchar((char)' ');
        }

        xputs("|\r\n");

        // Move on one row.
        pnt  += dispwidth;
        addr += dispwidth;

        // User abort (ESC), pause (Space) or all done?
        //
        keyIn = getserial_nonblocking();
        if(keyIn == ' ')
        {
            do {
                keyIn = getserial_nonblocking();
            } while(keyIn != ' ' && keyIn != 0x1b);
        }
        // Escape key pressed, exit with 0 to indicate this to caller.
        if (keyIn == 0x1b)
        {
            return(0);
        }

        // End of buffer, exit the loop.
        if(pnt >= (memaddr + memsize))
        {
            break;
        }
    }

    // Normal exit, return -1 to show no key pressed.
    return(-1);
}
#endif

// Method to scan a directory and return the list of filenames present therein.
//
#if defined(BUILTIN_FS_STATUS) && BUILTIN_FS_STATUS == 1
static FRESULT scan_files(char* path)    /* Pointer to the working buffer with start path */
{
    DIR     dirs;
    int     i;
    FILINFO Finfo;
    FRESULT fr;

    fr = f_opendir(&dirs, path);
    if (fr == FR_OK) {
        while (((fr = f_readdir(&dirs, &Finfo)) == FR_OK) && Finfo.fname[0]) {
            if (Finfo.fattrib & AM_DIR) {
                AccDirs++;
                i = strlen(path);
                path[i] = '/'; strcpy(path+i+1, Finfo.fname);
                fr = scan_files(path);
                path[i] = 0;
                if (fr != FR_OK) break;
            } else {
                AccFiles++;
                AccSize += Finfo.fsize;
            }
        }
    }

    return fr;
}

// Method to print out the logical drive status information.
//
FRESULT printFatFSStatus(char *path)
{
    DIR      dirs;
    uint32_t labelPtr;
    uint32_t dspacePtr;
    int      i;
    FATFS    *fsPtr;
    FILINFO  Finfo;
    FRESULT  fr0;
    FRESULT  fr1;

    // Get space information
    fr0 = f_getfree(path, (DWORD*)&dspacePtr, &fsPtr);

    if(!fr0)
    {
        xprintf("FAT type = %s\nBytes/Cluster = %lu\nNumber of FATs = %u\n"
                "Root DIR entries = %u\nSectors/FAT = %lu\nNumber of clusters = %lu\n"
                "Volume start (lba) = %lu\nFAT start (lba) = %lu\nDIR start (lba,clustor) = %lu\nData start (lba) = %lu\n\n",
                fileSystemTypeTable[fsPtr->fs_type], (DWORD)fsPtr->csize * SECTOR_SIZE, fsPtr->n_fats,
                fsPtr->n_rootdir, fsPtr->fsize, fsPtr->n_fatent - 2,
                fsPtr->volbase, fsPtr->fatbase, fsPtr->dirbase, fsPtr->database);

        #if FF_USE_LABEL
        // Get disk label information.
        fr0 = f_getlabel(path, (char*)fsBuff, (DWORD*)&labelPtr);

        if(!fr0)
        {
            xprintf(fsBuff[0] ? "Volume name is %s\n" : "No volume label\n", fsBuff);
            xprintf("Volume S/N is %04X-%04X\n", (WORD)((DWORD)labelPtr >> 16), (WORD)(labelPtr & 0xFFFF));
        }
        #endif

        xputs("...");

        // Get number of files, directories and space used.
        AccSize = AccFiles = AccDirs = 0;
        strcpy((char*)fsBuff, path);
        fr1 = scan_files((char*)fsBuff);
    }

    if(!fr0 && !fr1)
    {
        xprintf("%u files, %lu bytes.\n%u folders.\n"
                "%lu KB total disk space.\n%lu KB available.\n",
                AccFiles, AccSize, AccDirs,
                (fsPtr->n_fatent - 2) * fsPtr->csize / 2, dspacePtr * fsPtr->csize / 2);
    }

    return(fr0 ? fr0 : (fr1 ?  fr1 : FR_OK));
}
#endif

// Method to print out the files in a directory of a given (or default) directory.
#if defined(BUILTIN_FS_DIRLIST) && BUILTIN_FS_DIRLIST == 1
FRESULT printDirectoryListing(char *path)
{
    // Locals.
    uint32_t   dirCount;
    uint32_t   fileCount;
    uint32_t   totalSize;
    DIR        Dir;
    FRESULT    fr0;
    FILINFO    fInfo;
    FATFS     *fsPtr;

    // Open the directory for given path (path == NULL -> current path).
    fr0 = f_opendir(&Dir, path);

    // No errors then process.
    if(!fr0)
    {
        totalSize = fileCount = dirCount = 0;
        do {
            // Get one entry in the directory.
            fr0 = f_readdir(&Dir, &fInfo);

            if(!fr0 && fInfo.fname[0])
            {
                if (fInfo.fattrib & AM_DIR) {
                    dirCount++;
                } else {
                    fileCount++; totalSize += fInfo.fsize;
                }
                xprintf("%c%c%c%c%c %u/%02u/%02u %02u:%02u %9lu  %s\n", 
                            (fInfo.fattrib & AM_DIR) ? 'D' : '-',
                            (fInfo.fattrib & AM_RDO) ? 'R' : '-',
                            (fInfo.fattrib & AM_HID) ? 'H' : '-',
                            (fInfo.fattrib & AM_SYS) ? 'S' : '-',
                            (fInfo.fattrib & AM_ARC) ? 'A' : '-',
                            (fInfo.fdate >> 9) + 1980, (fInfo.fdate >> 5) & 15, fInfo.fdate & 31,
                            (fInfo.ftime >> 11), (fInfo.ftime >> 5) & 63,
                            (DWORD)fInfo.fsize, 
                            fInfo.fname);
            }
        } while(!fr0 && fInfo.fname[0]);

        if(!fr0)
        {
            xprintf("%4u File(s),%10lu bytes total\n%4u Dir(s)", fileCount, totalSize, dirCount);
            if (f_getfree(path, (DWORD*)&totalSize, &fsPtr) == FR_OK)
            {
                xprintf(", %10luKiB free\n", totalSize * fsPtr->csize / 2);
            }
        }
    }
    return(fr0 ? fr0 : FR_OK);
}
#endif

// Method to concatenate two source files into one destination file.
//
#if defined(BUILTIN_FS_CONCAT) && BUILTIN_FS_CONCAT == 1
FRESULT fileConcatenate(char *src1, char *src2, char *dst)
{
    // Locals.
    //
    FIL        File[3];
    uint32_t   dstSize;
    uint32_t   readSize;
    uint32_t   writeSize;
    FRESULT    fr0;
    FRESULT    fr1;
    FRESULT    fr2;
   
    // Sanity check on filenames.
    if(src1 == NULL || src2 == NULL || dst == NULL)
        return(FR_INVALID_PARAMETER);

    // Try and open the source files and create the destination file.
    fr0 = f_open(&File[0], src1, FA_OPEN_EXISTING | FA_READ);
    fr1 = f_open(&File[1], src2, FA_OPEN_EXISTING | FA_READ);
    fr2 = f_open(&File[2], dst, FA_CREATE_ALWAYS | FA_WRITE);

    // If no errors in opening the files, proceed with concatenation.
    if(!fr0 && !fr1 && !fr2)
    {
        TIMER_MILLISECONDS_UP = 0;
        dstSize = 0;
        for (;;) {
            fr0 = f_read(&File[0], fsBuff, SECTOR_SIZE, &readSize);
            if (fr0 || readSize == 0) break;              // error or eof
            fr2 = f_write(&File[2], fsBuff, readSize, &writeSize);
            dstSize += writeSize;
            if (fr2 || writeSize < readSize) break;       // error or disk full
        }
        if(!fr0 && !fr2)
        {
            for (;;) {
                fr1 = f_read(&File[1], fsBuff, SECTOR_SIZE, &readSize);
                if (fr1 || readSize == 0) break;          // error or eof
                fr2 = f_write(&File[2], fsBuff, readSize, &writeSize);
                dstSize += writeSize;
                if (fr2 || writeSize < readSize) break;   // error or disk full
            }
        }
    }

    // Close to sync files.
    f_close(&File[0]);
    f_close(&File[1]);
    f_close(&File[2]);
 
    // Any errors occured, dont print out timings.
    if(!fr0 && !fr1 && !fr2)
        printBytesPerSec(dstSize, TIMER_MILLISECONDS_UP, "copied");

    return(fr0 ? fr0 : (fr1 ? fr1 : (fr2 ? fr2 : FR_OK)));
}
#endif

// Method to copy a file to a destination. The filenames should be fully qualified if using
// multiple drives.
//
#if defined(BUILTIN_FS_COPY) && BUILTIN_FS_COPY == 1
FRESULT fileCopy(char *src, char *dst)
{
    // Locals.
    //
    FIL        File[2];
    uint32_t   dstSize;
    uint32_t   readSize;
    uint32_t   writeSize;
    FRESULT    fr0;
    FRESULT    fr1;
    
    // Sanity check on filenames.
    if(src == NULL || dst == NULL)
        return(FR_INVALID_PARAMETER);
    
    // Try and open the source file and create the destination file.
    fr0 = f_open(&File[0], src, FA_OPEN_EXISTING | FA_READ);
    fr1 = f_open(&File[1], dst, FA_CREATE_ALWAYS | FA_WRITE);
   
    // If no errors in opening the files, proceed with concatenation.
    if(!fr0 && !fr1)
    {
        TIMER_MILLISECONDS_UP = 0;
        dstSize = 0;
        for (;;) {
            fr0 = f_read(&File[0], fsBuff, SECTOR_SIZE, &readSize);
            if (fr0 || readSize == 0) break;              // error or eof
            fr1 = f_write(&File[1], fsBuff, readSize, &writeSize);
            dstSize += writeSize;
            if (fr1 || writeSize < readSize) break;       // error or disk full
        }
    }

    // Close to sync files.
    f_close(&File[0]);
    f_close(&File[1]);

    // Any errors occured, close files and return error code else return OK.
    if(!fr0 && !fr1)
        printBytesPerSec(dstSize, TIMER_MILLISECONDS_UP, "copied");

    return(fr0 ? fr0 : (fr1 ? fr1 : FR_OK));
}
#endif

// Method to extract a portion of a source file and write it into a destination file.
// multiple drives.
//
#if defined(BUILTIN_FS_XTRACT) && BUILTIN_FS_XTRACT == 1
FRESULT fileXtract(char *src, char *dst, uint32_t startPos, uint32_t len)
{
    // Locals.
    //
    FIL        File[2];
    uint32_t   dstSize;
    uint32_t   sizeToRead;
    uint32_t   readSize;
    uint32_t   writeSize;
    FRESULT    fr0;
    FRESULT    fr1;
    
    // Sanity check on filenames.
    if(src == NULL || dst == NULL)
        return(FR_INVALID_PARAMETER);
    
    // Try and open the source file and create the destination file.
    fr0 = f_open(&File[0], src, FA_OPEN_EXISTING | FA_READ);
    fr1 = f_open(&File[1], dst, FA_CREATE_ALWAYS | FA_WRITE);

    // If no errors in opening the files, proceed with copying.
    if(!fr0 && !fr1)
    {
        TIMER_MILLISECONDS_UP = 0;
        dstSize = 0;

        // Seek to start position in file and commence copying.
        fr0 = f_lseek(&File[0], startPos);
        if(!fr0)
        {
            for (;;) {
                sizeToRead = (len-dstSize) > SECTOR_SIZE ? SECTOR_SIZE : len - dstSize;
                fr0 = f_read(&File[0], fsBuff, sizeToRead, &readSize);

                if (fr0 || readSize == 0) break;              // error or eof

                fr1 = f_write(&File[1], fsBuff, readSize, &writeSize);
                dstSize += writeSize;
                if (fr1 || writeSize < readSize) break;       // error or disk full
            }
        }
    }

    // Close to sync files.
    f_close(&File[0]);
    f_close(&File[1]);

    // Any errors occured, dont print out timings.
    if(!fr0 && !fr1)
        printBytesPerSec(dstSize, TIMER_MILLISECONDS_UP, "copied");

    return(fr0 ? fr0 : (fr1 ? fr1 : FR_OK));
}
#endif

// Method to cat/output a file to the screen.
//
#if defined(BUILTIN_FS_CAT) && BUILTIN_FS_CAT == 1
FRESULT fileCat(char *src)
{
    // Locals.
    //
    FIL        File[1];
    uint32_t   readSize;
    FRESULT    fr0;
    
    // Sanity check on filenames.
    if(src == NULL)
        return(FR_INVALID_PARAMETER);
    
    // Try and open the source file.
    fr0 = f_open(&File[0], src, FA_OPEN_EXISTING | FA_READ);
   
    // If no errors in opening the files, proceed with reading.
    if(!fr0)
    {
        while ((fr0 = f_read(&File[0], fsBuff, 80, &readSize)) == FR_OK)
        {
            xputs(fsBuff);
            if (readSize != 80) break;
        }
        xputs("\n");
    }

    // Close to sync files.
    f_close(&File[0]);

    // Any errors occured, pass back to caller.
    return(fr0 ? fr0 : FR_OK);
}
#endif

// Method to load a file into memory.
//
#if defined(BUILTIN_FS_LOAD) && BUILTIN_FS_LOAD == 1
FRESULT fileLoad(char *src, uint32_t addr, uint8_t showStats)
{
    // Locals.
    //
    FIL        File[1];
    uint32_t   loadSize;
    uint32_t   readSize;
    char      *memPtr = (char *)addr;
    FRESULT    fr0;
    
    // Sanity check on filenames.
    if(src == NULL || addr < 0x400)
        return(FR_INVALID_PARAMETER);
    
    // Try and open the source file.
    fr0 = f_open(&File[0], src, FA_OPEN_EXISTING | FA_READ);
   
    // If no errors in opening the file, proceed with reading and loading into memory.
    if(!fr0)
    {
        TIMER_MILLISECONDS_UP = 0;
        loadSize = 0;
        for (;;) {
            fr0 = f_read(&File[0], memPtr, SECTOR_SIZE, &readSize);
            if (fr0 || readSize == 0) break;   /* error or eof */
            loadSize += readSize;
            memPtr += readSize;
        }
    }

    // Close to sync files.
    f_close(&File[0]);
 
    // Any errors occured, dont print out timings.
    if(!fr0 && showStats)
        printBytesPerSec(loadSize, TIMER_MILLISECONDS_UP, "read");

    return(fr0 ? fr0 : FR_OK);
}
#endif

// Method to save memory contents into a file.
//
#if defined(BUILTIN_FS_SAVE) && BUILTIN_FS_SAVE == 1
FRESULT fileSave(char *dst, uint32_t addr, uint32_t len)
{
    // Locals.
    //
    FIL        File[1];
    uint32_t   saveSize;
    uint32_t   writeSize;
    uint32_t   sizeToWrite;
    char      *memPtr = (char *)addr;
    FRESULT    fr0;
    
    // Sanity check on filenames.
    if(dst == NULL || len == 0)
        return(FR_INVALID_PARAMETER);
    
    // Try and create the destination file.
    fr0 = f_open(&File[0], dst, FA_CREATE_ALWAYS | FA_WRITE);
   
    // If no errors in creating the file, proceed with reading memory and saving.
    if(!fr0)
    {
        TIMER_MILLISECONDS_UP = 0;
        saveSize = 0;
        for (;;) {
            sizeToWrite = (len-saveSize) > SECTOR_SIZE ? SECTOR_SIZE : len - saveSize;
            fr0 = f_write(&File[0], (char *)memPtr, sizeToWrite, &writeSize);
            saveSize += writeSize;
            memPtr += writeSize;
            if (fr0 || writeSize < sizeToWrite || saveSize >= len) break;       // error, disk full or range written.
        }
    }

    // Close to sync files.
    f_close(&File[0]);
 
    // Any errors occured, dont print out timings.
    if(!fr0)
        printBytesPerSec(saveSize, TIMER_MILLISECONDS_UP, "written");

    return(fr0 ? fr0 : FR_OK);
}
#endif

// Method to dump a file in hex.
//
#if defined(BUILTIN_FS_DUMP) && BUILTIN_FS_DUMP == 1
FRESULT fileDump(char *src, uint32_t width)
{
    // Locals.
    //
    FIL        File[1];
    uint32_t   sizeToRead;
    uint32_t   loadSize;
    uint32_t   readSize;
    FRESULT    fr0;
    
    // Sanity check on parameters.
    if(src == NULL || (width != 8 && width != 16 && width != 32))
        return(FR_INVALID_PARAMETER);
    
    // Try and open the source file.
    fr0 = f_open(&File[0], src, FA_OPEN_EXISTING | FA_READ);
   
    // If no errors in opening the file, proceed with reading into the buffer then printing out buffer in hex.
    if(!fr0)
    {
        TIMER_MILLISECONDS_UP = 0;
        loadSize = 0;
        for (;;) {
            sizeToRead = (f_size(&File[0])-loadSize) > SECTOR_SIZE ? SECTOR_SIZE : f_size(&File[0]) - loadSize;
            fr0 = f_read(&File[0], fsBuff, sizeToRead, &readSize);

            if (fr0 || readSize == 0) break;   /* error or eof */
            if(memoryDump((uint32_t)fsBuff, readSize, width, loadSize, 32) == 0) { break; }
            loadSize += readSize;
        }
    }

    // Close to sync files.
    f_close(&File[0]);
 
    // Any errors occured, dont print out timings.
    if(!fr0)
        printBytesPerSec(loadSize, TIMER_MILLISECONDS_UP, "read");

    return(fr0 ? fr0 : FR_OK);
}
#endif

extern uint32_t _memreg; 

// Method to load a file into memory and execute it.
//
#if defined(BUILTIN_FS_EXEC) && BUILTIN_FS_EXEC == 1
uint32_t fileExec(char *src, uint32_t addr, uint32_t execAddr, uint8_t execMode, uint32_t param1, uint32_t param2, uint32_t G, uint32_t cfg)
{
    // Locals.
    //
    uint32_t   retCode = 0xffffffff;
    uint32_t   (*func)(uint32_t, uint32_t, uint32_t *, uint32_t, uint32_t) = (FRESULT (*)(uint32_t, uint32_t, uint32_t *, uint32_t, uint32_t))execAddr;
    void      *gotoptr       = (void *)execAddr;
    FRESULT    fr0;
    // Load the file.
    fr0 = fileLoad(src, addr, 0);

    // If no errors occurred, 
    if(!fr0)
    {
        switch(execMode)
        {
            // Call the loaded program entry address, return expected.
            case EXEC_MODE_CALL:
                retCode = func(param1, param2, &_memreg, G, cfg);
                break;

            // Jump to the loaded program entry address, no return expected.
            case EXEC_MODE_JMP: 
                goto *gotoptr;
                break;

            default:
                break;
        }
    }

    return(retCode);
}
#endif

// Method to read an open file block into buffer.
//
#if defined(BUILTIN_FS_READ) && BUILTIN_FS_READ == 1
FRESULT fileBlockRead(FIL *fp, uint32_t len)
{
    // Locals.
    //
    uint32_t   loadSize = len;
    uint32_t   sizeToRead;
    uint32_t   readSize;
    FRESULT    fr0 = FR_OK;
    
    // Sanity check on filehandle.
    if(fp == NULL || len > SECTOR_SIZE)
        return(FR_INVALID_PARAMETER);

    // Load the requested data from the file into the buffer in the given blockLen chunks.
    loadSize = 0;
    f_lseek(fp, 0);
    TIMER_MILLISECONDS_UP = 0;
    while (loadSize && !fr0) {
        if (loadSize >= blockLen) { sizeToRead = blockLen; loadSize -= blockLen; }
        else                      { sizeToRead = (WORD)loadSize; loadSize = 0; }
        fr0 = f_read(fp, &fsBuff[loadSize], sizeToRead, &readSize);
        if(!fr0)
        {
            loadSize += readSize;
            if (sizeToRead != readSize) break;
        }
    }
    
    // Any errors occured, dont print out timings.
    if(!fr0)
        printBytesPerSec(loadSize, TIMER_MILLISECONDS_UP, "read");

    return(fr0 ? fr0 : FR_OK);
}
#endif

// Method to write a portion of the buffer into an open file.
//
#if defined(BUILTIN_FS_WRITE) && BUILTIN_FS_WRITE == 1
FRESULT fileBlockWrite(FIL *fp, uint32_t len)
{
    // Locals.
    //
    uint32_t   saveSize = len;
    uint32_t   sizeToWrite;
    uint32_t   writeSize;
    FRESULT    fr0 = FR_OK;

    // Sanity check on filehandle.
    if(fp == NULL || len > SECTOR_SIZE)
        return(FR_INVALID_PARAMETER);

    // Save the requested data into the file at the current file position.
    TIMER_MILLISECONDS_UP = 0;
    while (saveSize && !fr0) {
        if (saveSize >= blockLen)    { sizeToWrite = blockLen; saveSize -= blockLen; }
        else                         { sizeToWrite = (WORD)saveSize; saveSize = 0; }
        fr0 = f_write(fp, fsBuff, sizeToWrite, &writeSize);
        if(!fr0)
        {
            if (sizeToWrite != writeSize) break;
        }
    }

    // Any errors occured, dont print out timings.
    if(!fr0)
        printBytesPerSec(len, TIMER_MILLISECONDS_UP, "written");

    return(fr0 ? fr0 : FR_OK);
}
#endif

// Method to dump out the current buffer in hex for inspection.
//
#if defined(BUILTIN_FS_INSPECT) && BUILTIN_FS_INSPECT == 1
FRESULT fileBlockDump(uint32_t offset, uint32_t len)
{
    // Locals.
    //
    uint32_t   dumpSize = (len == 0 ? SECTOR_SIZE - offset : len);
    uint32_t   sizeToWrite;
    uint32_t   writeSize;
    FRESULT    fr0 = FR_OK;
    
    // Sanity check on parameters.
    if(offset > SECTOR_SIZE || (offset+dumpSize) > SECTOR_SIZE)
        return(FR_INVALID_PARAMETER);

    // Dump out the memory.
    memoryDump((uint32_t)&fsBuff[offset], dumpSize, 16, offset, 16);

    return(FR_OK);
}
#endif

// Method to set the block length to operate with on read/write block functions.
//
FRESULT fileSetBlockLen(uint32_t len)
{
    // Sanity check on parameters.
    if(len == 0 || len > SECTOR_SIZE)
        return(FR_INVALID_PARAMETER);

    // Set length.
    blockLen = len;

    // All ok.
    return(FR_OK);
}

#endif // USE_SDCARD

// Method to output a help page based on the current set of enabled commands. This is done via
// the group and command tables defined in the header.
#if defined(BUILTIN_MISC_HELP) && BUILTIN_MISC_HELP == 1
void displayHelp(char *cmd)
{
    uint8_t gidx;
    uint8_t cidx;
    uint8_t hidx;
    uint8_t dispColumn = 0;
    uint8_t noParam;
    uint8_t matchCmd;
    uint8_t matchGroup;
    char    cmdSynopsis[50];

    // Display the program details.
    if(*cmd == 0x0) printVersion(0);

    // Parameter given?
    noParam = *cmd == 0x0 ? 1 : 0;

    // Go through all the groups, outputting group at at time.
    for (gidx=0; gidx < NGRPKEYS; gidx++)
    {
        t_groupstruct *grpsym = &groupTable[gidx];
        dispColumn = 0;

        // Any matches on Group filter?
        matchGroup = strstr(grpsym->name, cmd) != NULL ? 1 : 0;

        if(noParam || (!noParam && matchGroup)) xprintf("[%s]\n", grpsym->name);
        for (cidx=0; cidx < NCMDKEYS; cidx++)
        {
            // Match on group key.
            t_cmdstruct *cmdsym = &cmdTable[cidx];

            // Any matches on Cmd filter?
            matchCmd = strstr(cmdsym->cmd, cmd) != NULL ? 1 : 0;

            if(grpsym->key == cmdsym->group && (noParam || (!noParam && (matchGroup || matchCmd))))
            {
                // Lookup the help text according to command key.
                for(hidx=0; hidx < NHELPKEYS && helpTable[hidx].key != cmdTable[cidx].key; hidx++);

                if(hidx < NHELPKEYS)
                {
                    t_helpstruct *helpsym = &helpTable[hidx];
                    strcpy(cmdSynopsis, cmdsym->cmd);
                    strcat(cmdSynopsis, " ");
                    strcat(cmdSynopsis, helpsym->params);
                    xprintf("%-40s %c %-40s", cmdSynopsis, cmdsym->builtin == 1 ? '-' : '*', helpsym->description);
                } else
                {
                    strcpy(cmdSynopsis, cmdsym->cmd);
                    strcat(cmdSynopsis, " No help available.");
                    xprintf("%-40s %c %-40s", cmdSynopsis, cmdsym->builtin == 1 ? '-' : '*', " No help available.");
                }
                if(dispColumn++ == 1)
                {
                    dispColumn = 0;
                    xputs("\n");
                }
            }
        }
        if(dispColumn == 1) { xputs("\n"); }
        if(noParam || (!noParam && matchGroup)) { xputs("\n"); }
    }
}
#endif

// Function to output the ZPUTA version information and optionally the 
// configured hardware details.
#if defined(ZPUTA) || (defined(BUILTIN_MISC_HELP) && BUILTIN_MISC_HELP == 1)
void printVersion(uint8_t showConfig)
{
    // Basic title showing name and Cpu Id.
  #if defined(ZPUTA) 
    xprintf("\n** %s (", PROGRAM_NAME);
    printZPUId(cfgSoC.zpuId);
    xprintf(" ZPU, rev %02x) %s %s **\n\n", (uint8_t)cfgSoC.zpuId,  VERSION, VERSION_DATE);
 
    // Show configuration if requested.
    if(showConfig)
    {
        showSoCConfig();
    }
  #else
    xprintf("\n** %s %s %s **\n\n", APP_NAME, VERSION, VERSION_DATE);
  #endif
}
#endif
