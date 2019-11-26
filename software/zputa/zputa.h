/////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            zputa.h
// Created:         December 2018
// Author(s):       Philip Smart
// Description:     ZPU test application.
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
#ifndef ZPUTA_H
#define ZPUTA_H

// Constants.

// Components to be embedded in the program.
//
#define BUILTIN_DEFAULT             1
// Disk low level components to be embedded in the program.
#define BUILTIN_DISK_DUMP           0
#define BUILTIN_DISK_STATUS         0
// Disk buffer components to be embedded in the program.
#define BUILTIN_BUFFER_DUMP         0
#define BUILTIN_BUFFER_EDIT         0
#define BUILTIN_BUFFER_READ         0
#define BUILTIN_BUFFER_WRITE        0
#define BUILTIN_BUFFER_FILL         0
#define BUILTIN_BUFFER_LEN          0
// Memory components to be embedded in the program.
#define BUILTIN_MEM_CLEAR           1
#define BUILTIN_MEM_COPY            0
#define BUILTIN_MEM_DIFF            0
#define BUILTIN_MEM_DUMP            1
#define BUILTIN_MEM_EDIT_BYTES      1
#define BUILTIN_MEM_EDIT_HWORD      1
#define BUILTIN_MEM_EDIT_WORD       1
#define BUILTIN_MEM_TEST            0
// Hardware components to be embedded in the program.
#define BUILTIN_HW_SHOW_REGISTER    0
#define BUILTIN_HW_TEST_TIMERS      0
// Filesystem components to be embedded in the program.
#define BUILTIN_FS_STATUS           0
#define BUILTIN_FS_DIRLIST          0
#define BUILTIN_FS_OPEN             0
#define BUILTIN_FS_CLOSE            0
#define BUILTIN_FS_SEEK             0
#define BUILTIN_FS_READ             0
#define BUILTIN_FS_CAT              0
#define BUILTIN_FS_INSPECT          0
#define BUILTIN_FS_WRITE            0
#define BUILTIN_FS_TRUNC            0
#define BUILTIN_FS_RENAME           0
#define BUILTIN_FS_DELETE           0
#define BUILTIN_FS_CREATEDIR        0
#define BUILTIN_FS_ALLOCBLOCK       0
#define BUILTIN_FS_CHANGEATTRIB     0
#define BUILTIN_FS_CHANGETIME       0
#define BUILTIN_FS_COPY             0
#define BUILTIN_FS_CHANGEDIR        0
#define BUILTIN_FS_CHANGEDRIVE      0
#define BUILTIN_FS_SHOWDIR          0
#define BUILTIN_FS_SETLABEL         0
#define BUILTIN_FS_CREATEFS         0
#define BUILTIN_FS_LOAD             1
#define BUILTIN_FS_DUMP             0
#define BUILTIN_FS_CONCAT           0
#define BUILTIN_FS_XTRACT           0
#define BUILTIN_FS_SAVE             0
#define BUILTIN_FS_EXEC             1
// Test components to be embedded in the program.
#define BUILTIN_TST_DHRYSTONE       0
#define BUILTIN_TST_COREMARK        0
// Miscellaneous components to be embedded in this program.
#define BUILTIN_MISC_HELP           0
#define BUILTIN_MISC_SETTIME        0

// Application execution constants.
//
#define APP_CMD_EXTENSION           "ZPU"
#define APP_CMD_LOAD_ADDR           ZPUTA_APPADDR
#define APP_CMD_EXEC_ADDR           ZPUTA_APPADDR
#define APP_CMD_BIN_DIR             "bin"
#define APP_CMD_BIN_DRIVE           0

// Prototypes.
void    interrupt_handler();
void    initTimer();
void    enableTimer();
void    PrintFSCode(FRESULT);
int     cmdProcessor(void);

// Global scope variables.
static struct stat           statbuf;
FRESULT                      fResult;
UINT                         bw;
static GLOBALS               G;
extern SOC_CONFIG            cfgSoC;

volatile UINT                Timer;                                    /* Performance timer (100Hz increment) */

#endif // ZPUTA_H
