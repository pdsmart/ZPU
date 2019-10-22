/////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            iocp.h
// Created:         December 2018
// Author(s):       Philip Smart
// Description:     IO Control Processor Bootstrap loader header.
//                                                         
// Credits:         
// Copyright:       (c) 2019 Philip Smart <philip.smart@net2net.org>
//
// History:         January 2019  - Initial module written for STORM processor then changed to ZPU.
//
/////////////////////////////////////////////////////////////////////////////////////////////////////////
// This source file is free software: you can redistribute it and/or modify
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
#ifndef IOCP_H
#define IOCP_H

// Constants
#define BOOT_FILE_NAME              "BOOT.ROM"
#define BOOT_TINY_FILE_NAME         "BOOTTINY.ROM"
#define BOOT_LOAD_ADDR              IOCP_APPADDR
#define BOOT_EXEC_ADDR              IOCP_APPADDR

// Global parameters.
FATFS                    FatFs;                           /* Filesystem object for the logical drive */

// Prototypes.
void enableTimer();
void interrupt_handler();
int  uploadToMemory(uint32_t, uint32_t);
int  cmdProcessor(void);

// Global scope variables.
extern SOC_CONFIG                   cfgSoC;

#endif // IOCP_H
