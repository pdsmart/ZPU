/////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            iocp.c
// Created:         January 2019
// Author(s):       Philip Smart
// Description:     ZPU bootloader, termed IOCP (IO Control Program).
//                  This program initialises the ZPU, allows basic interaction such as program 
//                  upload and transfers control to a main application if available.
//                  On startup, if no intput (via the serial console) has been detected within 1 second
//                  and an application is stored in BRAM or available via SD card (which it loads),
//                  control is transferred to this program.
//
// Credits:         
// Copyright:       (c) 2019 Philip Smart <philip.smart@net2net.org>
//
// History:         January 2019   - Initial script written.
//                  July 2019      - Stripped down to the bare minimum, all other functionality moved
//                                   into the testapp.
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
#include <stdlib.h>
#include <zpu-types.h>
#include "zpu_soc.h"
#include "uart.h"
#include "interrupts.h"
#include "pff.h"            /* Declarations of FatFs API */
#include "diskio.h"
#include <string.h>
#include "simple_utils.h"
#include "iocp.h"

// Version info.
#define VERSION      "v1.5"
#define VERSION_DATE "29/08/2019"

// Method to process interrupts. This involves reading the interrupt status register and then calling
// the handlers for each triggered interrupt. A read of the interrupt controller clears the interrupt pending
// register so new interrupts will be processed after this method exits.
//
#if !defined(FUNCTIONALITY) || FUNCTIONALITY <= 1
static volatile unsigned int autobootTimer = 0;
void interrupt_handler()
{
    // Read the interrupt controller to find which devices caused an interrupt.
    //
    uint32_t intr = INTERRUPT_STATUS(INTR0);

    // Prevent additional interrupts.
    DisableInterrupts();

    if(INTR_IS_TIMER(intr))
    {
        autobootTimer = autobootTimer + 1;
    }

    // Enable new  interrupts.
    EnableInterrupts();
}

// Method to enable the timer.
//
void enableTimer()
{
    OPTIONAL(puts("Enabling timer...\n"));
    TIMER_ENABLE(TIMER1) = 1;               // Enable timer 1
}
#endif

#if !defined(FUNCTIONALITY) || FUNCTIONALITY == 0
// Function to upload an application into memory from the serial channel in binary.
//
int uploadToMemory(uint32_t memAddr, uint32_t memSize)
{
    // Locals.
    uint8_t   resultCode = 1;

    // Indicate mode selected and instructions to start upload.
    //
    OPTIONAL(puts("Binary upload, waiting...\n"));

    // Initialise CRC.
    //
    uint32_t crcDst = crc32_init();

    // Wait for start sequence.
    //
    int start_seq = 0;
    while(start_seq == 0)
    {
        if(getserial() == 'I')
            if(getserial() == 'O')
                if(getserial() == 'C')
                    if(getserial() == 'P')
                    {
                        start_seq = 1;
                    }
    }

    // Get size of image and validate.
    //
    uint32_t image_size = get_dword();
    if (image_size >  memSize-8)
    {
        puts(" ERROR! Upload too big!\n\n");
    } else
    {
        // Get CRC of image.
        //
        uint32_t crcSrc = get_dword();

        // Read in image_size words and store.
        //
        uint32_t data_pointer = memAddr;
        uint32_t count = image_size;
        uint32_t word;
        while(count > 0)
        {
            word = get_dword();
            *(uint32_t *)data_pointer = word;
            crcDst = crc32_addword(crcDst, word);
            data_pointer = data_pointer + 1;
            count-=4;
        }
        crcDst = ~crcDst;
 
        // Short delay to allow uploader to terminate.
        //
        //delay(1000);

        // Debug output to verify data.
        OPTIONAL(dbg_puts("Image_Size="));
        OPTIONAL(dbg_printdhex(image_size));
        OPTIONAL(dbg_puts(", "));
        OPTIONAL(dbg_puts("Source CRC="));
        OPTIONAL(dbg_printdhex(crcSrc));
        OPTIONAL(dbg_puts(", Destination CRC="));
        OPTIONAL(dbg_printdhex(crcDst));
        OPTIONAL(dbg_puts("\n"));

        // If CRCs dont match then indicate failure.
        if(crcSrc != crcDst)
        {
            puts("CRC mismatch.\r\n");
        } else
            resultCode = 0;
    }

    // Return success (0) or fail (1).
    return(resultCode);
}
#endif

// Function to output the IOCP version information and optionally the 
// configured hardware details.
#if !defined(FUNCTIONALITY) || FUNCTIONALITY <= 2
void printVersion(uint8_t showConfig)
{
  #if FUNCTIONALITY == 0
    // Basic title showing name and Cpu Id.
    puts("\n** IOCP BIOS (");
    printZPUId(cfgSoC.zpuId);
    puts(" ZPU, rev");
    printhexbyte((uint8_t)cfgSoC.zpuId);
    puts(") " VERSION " " VERSION_DATE " **\n");

    // Show configuration if requested.
    if(showConfig)
    {
        showSoCConfig();
    }
  #else
    puts("IOCP " VERSION " " VERSION_DATE "\n");
  #endif
}
#endif

// Interactive command processor. Allow user to input a command and execute accordingly.
//
#if !defined(FUNCTIONALITY) || FUNCTIONALITY <= 1
int cmdProcessor(void)
{
    int8_t            funcSelect;
    int8_t            cfgAvail = 0;
    uint32_t          startAppAddr = 0;
    uint32_t          memAddr;
    FILINFO           fno;
    FRESULT           rc;
    DIR               dir;

    // Initial prompt.
    puts("* ");
    while(1)
    {
        // console input
        funcSelect = getserial_nonblocking();
        if(funcSelect != -1)
        {
            putchar((char)funcSelect);
            puts("\n");
        }

        // Execute according to key selection.
        switch((char)funcSelect)
        {
            // Boot from Boot BRAM (start application)
            case '0':
                startAppAddr = BRAM_APP_START_ADDR;
                break;
               
            // Boot from RAM (start application)
            case '1':
                startAppAddr = cfgSoC.addrRAM;
                break;

  #if FUNCTIONALITY == 0
            // load bram via UART0
            case '2':
                // If BRAM is implemented then upload to the application area with limit 512 bytes below stack frame.
                if(cfgSoC.implBRAM)
                    uploadToMemory(cfgSoC.addrBRAM + BRAM_APP_START_ADDR, cfgSoC.sizeBRAM - BRAM_APP_START_ADDR - 504);
                break;

            case '3':
                // If RAM or DRAM is implemented then upload with size limit 512 bytes below stack frame.
                if(cfgSoC.implRAM || cfgSoC.implDRAM)
                    uploadToMemory(cfgSoC.addrRAM, cfgSoC.sizeRAM - 504);
                break;
  #endif

            // BRAM Memory dump
            case '4':
                if(cfgSoC.implInsnBRAM || cfgSoC.implBRAM)
                {
                    puts("Dump BRAM Memory\n");
                    memoryDump(cfgSoC.addrBRAM, cfgSoC.sizeBRAM);
                    puts("\n\nDumping completed.\n\n");
                } else
                {
                    OPTIONAL(puts("BRAM memory not implemented.\n"));
                }
                break;
                
            // Stack Memory dump - whichever memory is being used, dump out the stack.
            case '5':
                puts("Dump Stack Memory\n");
                memoryDump(cfgSoC.stackStartAddr-504, cfgSoC.stackStartAddr+8);
                puts("\n\nDumping completed.\n\n");
                break;
                
            // RAM Memory dump
            case '6':
                if(cfgSoC.implRAM)
                {
                    puts("Dump RAM\n");
                    memoryDump(cfgSoC.addrRAM, cfgSoC.sizeRAM);
                    puts("\n\nDumping completed.\n\n");
                } else
                {
                    OPTIONAL(puts("RAM memory not implemented.\n"));
                }
                break;
               
            // Clear BRAM.
            case 'C':
                if(cfgSoC.implBRAM && cfgSoC.implInsnBRAM)
                {
                    puts("Clearing BRAM Memory\n");
                    for(memAddr=cfgSoC.addrBRAM; memAddr < (cfgSoC.addrBRAM+cfgSoC.sizeBRAM); memAddr+=4)
                    {
                        *(uint32_t *)(memAddr) = 0x00000000;
                    }
                } else
                {
                    puts("BRAM memory not implemented.\n");
                }
                break;
                
            // Clear RAM.
            case 'c':
                if(cfgSoC.implRAM)
                {
                    puts("Clearing RAM\n");
                    for(memAddr=cfgSoC.addrRAM; memAddr < (cfgSoC.addrRAM+cfgSoC.sizeRAM); memAddr+=4)
                    {
                        *(uint32_t *)(memAddr) = 0xaa55ff00;
                    }
                } else
                {
                    puts("RAM memory not implemented.\n");
                }
                break;

            // List the SD directory contents.
            case 'd':
                rc = pf_opendir(&dir, "");
                if(!rc)
                {
	                for (;;) {
		                rc = pf_readdir(&dir, &fno);	/* Read a directory item */
		                if (rc || !fno.fname[0]) break;	/* Error or end of dir */
		                if (fno.fattrib & AM_DIR)
                        {
			                puts("   <dir>  "); puts(fno.fname); puts("\n");
                        } else
                        {
			                printdhex(fno.fsize); puts("  "); puts(fno.fname); puts("\n");
                        }
	                }
                }
                if(rc) { puts("Error: "); printhex(rc); puts("\n"); }
                break;
                
            // Reset the system.
            case 'R':
                puts("Restarting...\n");
                void *strtptr = (void *)0x00000;
                goto *strtptr;
                break;
             
            // Help screen
            case 'h':
                printVersion(false);
                puts("0: Execute App in Boot BRAM.                   1: Execute App in RAM\n"
                     "2: Upload App to BRAM.                         3: Upload App to RAM.\n"
                     "4: Dump BRAM Memory.                           5: Dump Stack Memory.\n"
                     "6: Dump RAM Memory.                            d: List SD directory.\n"
                     "c: Clear RAM.                                  C: Clear BRAM App Memory.\n"
                     "h: Show this screen.                           i: Configuration information.\n"
                     "R: Reset system.\n");
                break;

            // Configuration information
            case 'i':
                printVersion(true);
                break;
            
            // No input
            case -1:
            default:
                break;
        }

        // If a key was pressed then re-output prompt for next key.
        //
        if(funcSelect != -1)
        {
            puts("* ");
        }

        // If the autoboot timer has expired then attempt to autoboot preloaded application.
        //
        if(autobootTimer > 5)
        {
            // If BRAM is implemented and the application program memory portion is not empty, execute it.
            if(cfgSoC.implBRAM && *(uint32_t *)(cfgSoC.addrBRAM + BRAM_APP_START_ADDR) != 0x00000000)
            {
                startAppAddr = cfgSoC.addrBRAM + BRAM_APP_START_ADDR;
            } else
            // Else if RAM is implemented (either as static/BRAM or DRAM) and the program memory is not empty, execute it.
            if((cfgSoC.implRAM || cfgSoC.implDRAM) && *(uint32_t *)(cfgSoC.addrRAM) != 0x00000000)
            {
                startAppAddr = cfgSoC.addrRAM;
            }
            OPTIONAL(if(startAppAddr != 0) { puts("..autobooting.\n");  });
        }
                        
        // Start application request
        if(startAppAddr != 0)
        {
            // Disable interrupts before starting application, application can reenable if needed.
            DisableInterrupt(INTR_TIMER);

            // Start application
            OPTIONAL(puts("\nStart App @ 0x"); printdhex(startAppAddr); putchar((int)'\n'));
            void *jmpptr = (void *)startAppAddr;
            goto *jmpptr;
        }
    }
}
#endif

// Main program entry point.
int main(int argc, char **argv)
{
    // Setup the required baud rate for the UART. Once the divider is loaded, a reset takes place within the UART.
    UART_BRGEN(UART0) = BAUDRATEGEN(UART0, 115200, 115200);
    UART_BRGEN(UART1) = BAUDRATEGEN(UART1, 115200, 115200);

    // Enable the RX/TX units and enable FIFO mode.
    UART_CTRL(UART0)  = UART_TX_FIFO_ENABLE | UART_TX_ENABLE | UART_RX_FIFO_ENABLE | UART_RX_ENABLE;
    UART_CTRL(UART1)  = UART_TX_FIFO_ENABLE | UART_TX_ENABLE | UART_RX_FIFO_ENABLE | UART_RX_ENABLE;

  #if !defined(FUNCTIONALITY) || FUNCTIONALITY <= 2
    // Ensure interrupts are disabled before configuring the SoC.
    DisableInterrupts();

    // Setup the configuration using the SoC configuration register if implemented otherwise the compiled internals.
    setupSoCConfig();
  #endif

    // Start the timer running and enable interrupts. The time count is used to decide if we autoboot.
  #if !defined(FUNCTIONALITY) || FUNCTIONALITY <= 1
    SetIntHandler(interrupt_handler);
    EnableInterrupt(0);

    // Intro screen, show title and configuration.
    printVersion(true);
  #endif

    // Try and mount the disk.
    if(pf_mount(&FatFs))
    {
      #if !defined(FUNCTIONALITY) || FUNCTIONALITY <= 2
        puts("Failed to mount disk.\n");
      #endif
    } else
    {
        // Try and open the source file. If no errors in opening the file, proceed with reading and loading into memory.
      #if !defined(FUNCTIONALITY) || FUNCTIONALITY == 3
        if(!pf_open(BOOT_TINY_FILE_NAME))
      #else
        if(!pf_open(BOOT_FILE_NAME))
      #endif
        {
            char      *memPtr        = (char *)BOOT_LOAD_ADDR;
            void      *gotoptr       = (void *)BOOT_EXEC_ADDR;
            uint32_t   readSize;
          
            // Indicate booting...
          #if !defined(FUNCTIONALITY) || FUNCTIONALITY <= 2
            puts("Boot SD\n");
          #endif

            // Load the application into memory and execute.
            //
            TIMER_MILLISECONDS_UP = 0;
            for (;;) {
                if(pf_read(memPtr, 512, &readSize)) break;  /* error */
                if(readSize == 0) break;                    /* eof */
                memPtr += readSize;
            }
            goto *gotoptr;
        } else
        {
          #if !defined(FUNCTIONALITY) || FUNCTIONALITY <= 1
            // Command processor. If it exits, then reset the CPU.
            cmdProcessor();
          #endif
        }
    }

    // Reboot as it is not normal if auto boot fails or the command processor terminates.
    void *rbtptr = (void *)0x00000000;
    goto *rbtptr;
}
// Should never get here...
