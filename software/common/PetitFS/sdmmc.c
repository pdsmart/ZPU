/////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            sdmmc.c
// Created:         June 2019
// Author(s):       ChaN (framework), Philip Smart (zpu SoC customisation)
// Description:     Functionality to enable connectivity between the PetitFS ((C) ChaN) and the ZPU SoC
//                  for SD drives. The majority of SD logic exists in hardware, this module provides
//                  the public interfaces to interact with the hardware.
//
// Credits:         
// Copyright:       (C) 2013, ChaN, all rights reserved - framework.
// Copyright:       (C) 2019 Philip Smart <philip.smart@net2net.org>
//
// History:         January 2019   - Initial script written for the STORM processor then changed to the ZPU.
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

#include "pff.h"                 /* Obtains integer types for Petit FatFs */
#include "diskio.h"              /* Common include file for FatFs and disk I/O layer */

/*-------------------------------------------------------------------------*/
/* Platform dependent macros and functions needed to be modified           */
/*-------------------------------------------------------------------------*/

#include "zpu-types.h"
#include "zpu_soc.h"
#include "uart.h"
//#include "utils.h"

/*--------------------------------------------------------------------------
   Module Private Functions
---------------------------------------------------------------------------*/

/* MMC/SD command (SPI mode) */
#define CMD0         (0)         /* GO_IDLE_STATE */
#define CMD1         (1)         /* SEND_OP_COND */
#define ACMD41       (0x80+41)   /* SEND_OP_COND (SDC) */
#define CMD8         (8)         /* SEND_IF_COND */
#define CMD9         (9)         /* SEND_CSD */
#define CMD10        (10)        /* SEND_CID */
#define CMD12        (12)        /* STOP_TRANSMISSION */
#define CMD13        (13)        /* SEND_STATUS */
#define ACMD13       (0x80+13)   /* SD_STATUS (SDC) */
#define CMD16        (16)        /* SET_BLOCKLEN */
#define CMD17        (17)        /* READ_SINGLE_BLOCK */
#define CMD18        (18)        /* READ_MULTIPLE_BLOCK */
#define CMD23        (23)        /* SET_BLOCK_COUNT */
#define ACMD23       (0x80+23)   /* SET_WR_BLK_ERASE_COUNT (SDC) */
#define CMD24        (24)        /* WRITE_BLOCK */
#define CMD25        (25)        /* WRITE_MULTIPLE_BLOCK */
#define CMD32        (32)        /* ERASE_ER_BLK_START */
#define CMD33        (33)        /* ERASE_ER_BLK_END */
#define CMD38        (38)        /* ERASE */
#define CMD55        (55)        /* APP_CMD */
#define CMD58        (58)        /* READ_OCR */
#define SECTOR_SIZE  512         /* Default size of an SD Sector */

static
DSTATUS Stat =  STA_NOINIT;      /* Disk status */

/*--------------------------------------------------------------------------
   Public Functions
---------------------------------------------------------------------------*/


/*-----------------------------------------------------------------------*/
/* Initialize Disk Drive                                                 */
/*-----------------------------------------------------------------------*/
DSTATUS disk_initialize ( void )
{
    uint32_t status;
//puts("In disk init\n");
    // Set the card type.
    SD_CMD(0) = SD_CMD_CARDTYPE_SDHC;

//puts("In disk init 1\n");
    // Issue the reset command to initialise the drive.
    SD_CMD(0) = SD_CMD_RESET;

//puts("In disk init 2\n");
    // Setup a 5 second delay count, if this timer expires then initialisation failed.
    TIMER_SECONDS_DOWN = 5;

//puts("In disk init 3\n");
    // Wait until the drive becomes ready.
    while(IS_SD_BUSY(0) && TIMER_SECONDS_DOWN > 0);

//puts("In disk init 4\n");
    // If there is an error code, then the drive didnt initialise.
    if(!(SD_STATUS(0) & SD_STATUS_ERROR) && TIMER_SECONDS_DOWN > 0)
        Stat = 0;

//puts("In disk init 5\n");
    return Stat;
}

/*-----------------------------------------------------------------------*/
/* Read Sector(s)                                                        */
/*-----------------------------------------------------------------------*/
DRESULT disk_readp( BYTE *buff,          /* Pointer to the data buffer to store read data */
                    DWORD sector,        /* Start sector number (LBA) */
                    UINT offset,         /* Byte offset to read from (0..511) */
                    UINT count    )      /* Number of bytes to read (ofs + cnt mus be <= 512) */
{
    BYTE     data;
    uint32_t status;
    uint32_t rxCount = 0;

    // Check the drive, if it hasnt been initialised then exit.
    if (Stat & STA_NOINIT) return RES_NOTRDY;

    // Setup a 5 second delay count, if this timer expires then reset and retry.
    TIMER_SECONDS_DOWN = 5;

    // Set the sector to retrieve.
    SD_ADDR(0) = sector;
    SD_CMD(0)  = SD_CMD_READ;

    // Receive all bytes until Busy goes inactive or timer timesout.
    do {
        status = SD_STATUS(0);
        if(status & SD_STATUS_DATA_VALID)
        {
            data = (uint8_t)SD_DATA(0);
            if(rxCount >= offset && count > 0)
            {
                *(BYTE *)(buff) = data;
                buff++;
                count--;
            }
            rxCount++;
        }
    } while((status & (SD_STATUS_BUSY|SD_STATUS_DATA_VALID)) != 0 && TIMER_SECONDS_DOWN > 0);

    // If we exitted due to a timeout reset and exit with last error.
    if(TIMER_SECONDS_DOWN == 0)
    {
        // Issue the reset command to initialise the drive.
        SD_CMD(0) = SD_CMD_RESET;

        // Wait until the drive becomes ready.
        while(IS_SD_BUSY(0));
    }

    // Return error if the last read failed.
    return status & SD_STATUS_ERROR ? RES_ERROR : TIMER_SECONDS_DOWN == 0 ? RES_ERROR : RES_OK;
}

/*-----------------------------------------------------------------------*/
/* Write Sector(s)                                                       */
/*-----------------------------------------------------------------------*/
DRESULT disk_writep( const BYTE *buff,    /* Pointer to the data to be written */
                     DWORD sector     )   /* Start sector number (LBA) or Number of bytes to send */
{
    uint32_t status;
    uint32_t txCount = 0;

    // Check the drive, if it hasnt been initialised then exit.
    if (Stat & STA_NOINIT) return RES_NOTRDY;

    // Setup a 5 second delay count, if this timer expires then reset and retry.
    TIMER_SECONDS_DOWN = 5;

    // Set the sector to retrieve.
    SD_ADDR(0) = sector;
    SD_CMD(0)  = SD_CMD_WRITE;

    // Send bytes upto sector limit or until busy goes inactive or timer times out.
    txCount = 0;
    do {
        status = SD_STATUS(0);

        if(status & SD_STATUS_DATA_REQ)
        {
            SD_DATA(0) = *buff;
            buff++;
            txCount++;
        }
    } while((status & SD_STATUS_BUSY) && TIMER_SECONDS_DOWN > 0);

    // If we exitted due to a timeout reset and exit with last error.
    if(TIMER_SECONDS_DOWN == 0)
    {
        // Issue the reset command to initialise the drive.
        SD_CMD(0) = SD_CMD_RESET;

        // Wait until the drive becomes ready.
        while(IS_SD_BUSY(0));
    }

    // Return error if the last write failed.
    return status & SD_STATUS_ERROR ? RES_ERROR : TIMER_SECONDS_DOWN == 0 ? RES_ERROR : RES_OK;
}
