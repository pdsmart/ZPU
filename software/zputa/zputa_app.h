/////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            zputa_app.h
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
#ifndef ZPUTA_APP_H
#define ZPUTA_APP_H

// Constants.
#define MAX_FILE_HANDLE             3              // Maximum number of file handles to open per logical drive.

// Global parameters accessible in applications.
typedef struct {
    uint8_t                  fileInUse;                                /* Flag to indicate if file[0] is in use. */
    FIL                      File[MAX_FILE_HANDLE];                    /* Maximum open file objects */
    FATFS                    FatFs[FF_VOLUMES];                        /* Filesystem object for each logical drive */
    BYTE                     Buff[512];                                /* Working buffer */
    DWORD                    Sector;                                   /* Sector to read */
} GLOBALS;

#endif // ZPUTA_APP_H
